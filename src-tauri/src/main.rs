mod ai;
mod dictionary;
mod platform;
mod store;

use dictionary::Card;
use rusqlite::Connection;
use serde::Serialize;
use std::sync::{
    Mutex,
    atomic::{AtomicBool, Ordering},
};
use store::{SavedWord, Settings};
use tauri::{
    Emitter, Manager, State,
    ipc::Channel,
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};
use tokio_util::sync::CancellationToken;

struct AppState {
    dictionary: Mutex<Connection>,
    database: Mutex<Connection>,
    request: Mutex<Option<(u64, CancellationToken)>>,
    pinned: AtomicBool,
    capturing: AtomicBool,
    previous_app: Mutex<String>,
}

#[derive(Serialize)]
struct Prepared {
    source: String,
    target: String,
    mode: String,
    card: Option<Card>,
}

#[derive(Clone, Serialize)]
struct EntryEvent {
    kind: String,
    text: String,
    error: String,
}

#[tauri::command]
fn prepare(
    app: tauri::AppHandle,
    state: State<AppState>,
    text: String,
    source: String,
    target: String,
) -> Result<Prepared, String> {
    if text.trim().is_empty() {
        return Err("请输入需要查询的文字。".into());
    }
    let local = dictionary::lookup(&state.dictionary.lock().unwrap(), &text)?;
    let source = if source == "auto" {
        if local.is_some() {
            "en".into()
        } else {
            platform::native(&app, "language", Some(&text))?
                .split('-')
                .next()
                .unwrap_or("")
                .to_string()
        }
    } else {
        source
    };
    if !["zh", "en", "ja", "ko", "fr", "de", "es", "ru", "it", "pt"].contains(&source.as_str()) {
        return Err("无法确定支持的源语言，请手动选择。".into());
    }
    let target = if target == "auto" {
        if source == "zh" { "en" } else { "zh" }.into()
    } else {
        target
    };
    if source == target {
        return Err("源语言和目标语言不能相同。".into());
    }
    let card = if source == "en" && target == "zh" {
        local
    } else {
        None
    };
    let word = text
        .trim()
        .chars()
        .all(|c| c.is_alphabetic() || c == '-' || c == '\'');
    let short = if ["zh", "ja", "ko"].contains(&source.as_str()) {
        text.chars().count() <= 4
    } else {
        text.chars().count() <= 40
    };
    let mode = if card.is_some() || word && short {
        "dictionary"
    } else {
        "translation"
    }
    .into();
    Ok(Prepared {
        source,
        target,
        mode,
        card,
    })
}

#[tauri::command]
async fn translate(
    state: State<'_, AppState>,
    id: u64,
    text: String,
    source: String,
    target: String,
    dictionary: bool,
    channel: Channel<ai::Chunk>,
) -> Result<String, String> {
    let settings = store::settings(&state.database.lock().unwrap())?;
    let key = ai::key()?;
    let cancel = CancellationToken::new();
    {
        let mut request = state.request.lock().unwrap();
        if let Some((_, previous)) = request.take() {
            previous.cancel();
        }
        *request = Some((id, cancel.clone()));
    }
    let result = ai::request(
        &settings,
        &key,
        &text,
        (&source, &target),
        dictionary,
        Some(channel),
        cancel,
    )
    .await?;
    if dictionary {
        #[derive(serde::Deserialize)]
        struct AiEntry {
            word: String,
            translation: String,
            definition: String,
        }
        let entry: AiEntry =
            serde_json::from_str(&result).map_err(|_| "AI 词典响应格式错误，请重试。")?;
        if entry.word.trim().is_empty() || entry.translation.trim().is_empty() {
            return Err("AI 未返回有效释义，请重试。".into());
        }
        serde_json::to_string(&Card {
            original: text,
            entry: dictionary::Entry {
                word: entry.word,
                phonetic: String::new(),
                translation: entry.translation,
                definition: entry.definition,
            },
            relations: vec![],
            confirmed: false,
            source: "AI 释义".into(),
        })
        .map_err(|e| e.to_string())
    } else {
        Ok(result)
    }
}

#[tauri::command]
fn cancel(state: State<AppState>, id: u64) {
    if let Some((current, token)) = state.request.lock().unwrap().as_ref()
        && *current == id
    {
        token.cancel();
    }
}

#[tauri::command]
fn shortcut_status(
    app: tauri::AppHandle,
    state: State<AppState>,
) -> Result<serde_json::Value, String> {
    let settings = store::settings(&state.database.lock().unwrap())?;
    let errors: Vec<_> = settings
        .shortcuts
        .iter()
        .filter(|shortcut| !app.global_shortcut().is_registered(shortcut.as_str()))
        .cloned()
        .collect();
    Ok(serde_json::json!({ "shortcut_errors": errors }))
}

#[tauri::command]
fn settings(app: tauri::AppHandle, state: State<AppState>) -> Result<serde_json::Value, String> {
    let settings = store::settings(&state.database.lock().unwrap())?;
    let errors = shortcut_status(app, state)?;
    Ok(
        serde_json::json!({ "settings": settings, "has_key": ai::key().is_ok(), "shortcut_errors": errors["shortcut_errors"] }),
    )
}

#[tauri::command]
fn save_settings(
    app: tauri::AppHandle,
    state: State<AppState>,
    settings: Settings,
    key: Option<String>,
) -> Result<(), String> {
    ai::validate(&settings)?;
    let new = settings
        .shortcuts
        .iter()
        .map(|s| s.parse::<Shortcut>().map_err(|e| e.to_string()))
        .collect::<Result<Vec<_>, _>>()?;
    if new
        .iter()
        .enumerate()
        .any(|(i, shortcut)| new[..i].contains(shortcut))
    {
        return Err("三个快捷键不能重复，原绑定已保留。".into());
    }
    let db = state.database.lock().unwrap();
    let previous = store::settings(&db)?;
    let old = previous
        .shortcuts
        .iter()
        .map(|s| s.parse::<Shortcut>().map_err(|e| e.to_string()))
        .collect::<Result<Vec<_>, _>>()?;
    let mut registered = Vec::new();
    for shortcut in new
        .iter()
        .filter(|s| !app.global_shortcut().is_registered(**s))
    {
        if let Err(error) = app.global_shortcut().register(*shortcut) {
            for shortcut in registered {
                let _ = app.global_shortcut().unregister(shortcut);
            }
            return Err(format!("快捷键注册失败，原绑定已保留：{error}"));
        }
        registered.push(*shortcut);
    }
    let result = (|| {
        store::save_settings(&db, &settings)?;
        if let Some(key) = key.filter(|key| !key.trim().is_empty())
            && let Err(error) = security_framework::passwords::set_generic_password(
                "app.glint.desktop",
                "api-key",
                key.trim().as_bytes(),
            )
        {
            store::save_settings(&db, &previous)?;
            return Err(format!("无法保存系统钥匙串：{error}"));
        }
        Ok(())
    })();
    if result.is_err() {
        for shortcut in registered {
            let _ = app.global_shortcut().unregister(shortcut);
        }
        return result;
    }
    for shortcut in old.iter().filter(|s| !new.contains(s)) {
        app.global_shortcut()
            .unregister(*shortcut)
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
async fn test_connection(settings: Settings, key: Option<String>) -> Result<(), String> {
    let key = key
        .filter(|s| !s.trim().is_empty())
        .map(Ok)
        .unwrap_or_else(ai::key)?;
    ai::request(
        &settings,
        &key,
        "Hello",
        ("en", "zh"),
        false,
        None,
        CancellationToken::new(),
    )
    .await?;
    Ok(())
}

#[tauri::command]
fn vocabulary(state: State<AppState>) -> Result<Vec<SavedWord>, String> {
    store::vocabulary(&state.database.lock().unwrap())
}

#[tauri::command]
fn save_word(state: State<AppState>, word: SavedWord) -> Result<(), String> {
    store::save_word(&state.database.lock().unwrap(), word)
}

#[tauri::command]
fn delete_word(state: State<AppState>, id: String) -> Result<(), String> {
    state
        .database
        .lock()
        .unwrap()
        .execute("DELETE FROM vocabulary WHERE id=?", [id])
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
async fn transfer_vocabulary(app: tauri::AppHandle, import: bool) -> Result<(), String> {
    use tauri_plugin_dialog::DialogExt;
    tauri::async_runtime::spawn_blocking(move || {
        let dialog = app.dialog().file().add_filter("Glint 生词本", &["json"]);
        let selection = if import {
            dialog.blocking_pick_file()
        } else {
            dialog
                .set_file_name("glint-vocabulary.json")
                .blocking_save_file()
        };
        let Some(selection) = selection else {
            return Ok(());
        };
        let path = selection.into_path().map_err(|e| e.to_string())?;
        let state = app.state::<AppState>();
        let mut db = state.database.lock().unwrap();
        if import {
            let words: Vec<SavedWord> =
                serde_json::from_slice(&std::fs::read(path).map_err(|e| e.to_string())?)
                    .map_err(|_| "不是有效的 Glint 生词本文件。")?;
            let transaction = db.transaction().map_err(|e| e.to_string())?;
            for word in words {
                store::save_word(&transaction, word)?;
            }
            transaction.commit().map_err(|e| e.to_string())?;
        } else {
            let data =
                serde_json::to_vec_pretty(&store::vocabulary(&db)?).map_err(|e| e.to_string())?;
            std::fs::write(path, data).map_err(|e| e.to_string())?;
        }
        Ok(())
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
fn pin(window: tauri::WebviewWindow, state: State<AppState>, pinned: bool) -> Result<(), String> {
    window
        .set_always_on_top(pinned)
        .map_err(|e| e.to_string())?;
    state.pinned.store(pinned, Ordering::SeqCst);
    Ok(())
}

#[tauri::command]
fn hide(
    app: tauri::AppHandle,
    window: tauri::WebviewWindow,
    state: State<AppState>,
) -> Result<(), String> {
    window.hide().map_err(|e| e.to_string())?;
    platform::native(&app, "restore", Some(&state.previous_app.lock().unwrap()))?;
    Ok(())
}

#[tauri::command]
fn copy(app: tauri::AppHandle, text: String) -> Result<(), String> {
    platform::native(&app, "copy", Some(&text)).map(|_| ())
}

#[tauri::command]
fn speak(text: String) -> Result<(), String> {
    use std::io::Write;
    let mut child = std::process::Command::new("/usr/bin/say")
        .stdin(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| e.to_string())?;
    child
        .stdin
        .take()
        .unwrap()
        .write_all(text.as_bytes())
        .map_err(|e| e.to_string())?;
    std::thread::spawn(move || {
        let _ = child.wait();
    });
    Ok(())
}

fn open_entry(app: &tauri::AppHandle, kind: &str) {
    let state = app.state::<AppState>();
    if state.capturing.swap(true, Ordering::SeqCst) {
        return;
    }
    let app = app.clone();
    let kind = kind.to_owned();
    tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<AppState>();
        let window = app.get_webview_window("main").unwrap();
        if let Ok(pid) = platform::native(&app, "front", None)
            && pid != std::process::id().to_string()
        {
            *state.previous_app.lock().unwrap() = pid;
        }
        let position = window.cursor_position().ok();
        if kind == "ocr" {
            let _ = window.hide();
        }
        let result = if kind == "selection" || kind == "ocr" {
            platform::native(&app, &kind, None)
        } else {
            Ok(String::new())
        };
        if result.as_ref().is_err_and(|error| error == "已取消截图") {
            let _ = platform::native(&app, "restore", Some(&state.previous_app.lock().unwrap()));
            state.capturing.store(false, Ordering::SeqCst);
            return;
        }
        if let Some(point) = position
            && let Ok(Some(monitor)) = app.monitor_from_point(point.x, point.y)
        {
            let origin = monitor.position();
            let size = monitor.size();
            let window_size = window
                .outer_size()
                .unwrap_or(tauri::PhysicalSize::new(480, 640));
            let x = point.x.max(origin.x as f64).min(
                (origin.x as f64 + size.width as f64 - window_size.width as f64)
                    .max(origin.x as f64),
            );
            let y = (point.y + 16.0).max(origin.y as f64).min(
                (origin.y as f64 + size.height as f64 - window_size.height as f64)
                    .max(origin.y as f64),
            );
            let _ = window.set_position(tauri::PhysicalPosition::new(x, y));
        }
        let (text, error) = match result {
            Ok(text) => (text, String::new()),
            Err(error) => (String::new(), error),
        };
        let _ = window.emit("entry", EntryEvent { kind, text, error });
        let _ = window.show();
        let _ = window.set_focus();
        state.capturing.store(false, Ordering::SeqCst);
    });
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, shortcut, event| {
                    if event.state() != ShortcutState::Released {
                        return;
                    }
                    let settings =
                        store::settings(&app.state::<AppState>().database.lock().unwrap());
                    if let Ok(settings) = settings
                        && let Some(index) = settings
                            .shortcuts
                            .iter()
                            .position(|s| s.parse::<Shortcut>().ok().as_ref() == Some(shortcut))
                    {
                        open_entry(app, ["selection", "input", "ocr"][index]);
                    }
                })
                .build(),
        )
        .setup(|app| {
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);
            let data = app.path().app_data_dir()?;
            std::fs::create_dir_all(&data)?;
            let db = Connection::open(data.join("glint.sqlite"))?;
            store::initialize(&db)?;
            let settings = store::settings(&db)?;
            let dictionary = Connection::open_with_flags(
                app.path()
                    .resource_dir()?
                    .join("resources/dictionary.sqlite"),
                rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
            )?;
            app.manage(AppState {
                dictionary: Mutex::new(dictionary),
                database: Mutex::new(db),
                request: Mutex::new(None),
                pinned: AtomicBool::new(false),
                capturing: AtomicBool::new(false),
                previous_app: Mutex::new(String::new()),
            });
            for shortcut in &settings.shortcuts {
                if let Err(error) = app.global_shortcut().register(shortcut.as_str()) {
                    eprintln!("快捷键 {shortcut} 注册失败：{error}");
                }
            }
            let settings_item = MenuItem::with_id(app, "settings", "设置", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "退出 Glint", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&settings_item, &quit])?;
            let mut rgba = vec![0; 22 * 22 * 4];
            for y in 0..22_usize {
                for x in 0..22_usize {
                    if x.abs_diff(11) + y.abs_diff(11) < 9
                        && (x.abs_diff(11) < 2
                            || y.abs_diff(11) < 2
                            || x.abs_diff(11) + y.abs_diff(11) < 5)
                    {
                        rgba[(y * 22 + x) * 4 + 3] = 255;
                    }
                }
            }
            TrayIconBuilder::new()
                .icon(tauri::image::Image::new_owned(rgba, 22, 22))
                .icon_as_template(true)
                .tooltip("Glint")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "settings" => open_entry(app, "settings"),
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if matches!(
                        event,
                        TrayIconEvent::Click {
                            button: MouseButton::Left,
                            button_state: MouseButtonState::Up,
                            ..
                        }
                    ) {
                        open_entry(tray.app_handle(), "input");
                    }
                })
                .build(app)?;
            Ok(())
        })
        .on_window_event(|window, event| match event {
            tauri::WindowEvent::CloseRequested { api, .. } => {
                api.prevent_close();
                let _ = window.hide();
            }
            tauri::WindowEvent::Focused(false) => {
                let state = window.state::<AppState>();
                if !state.pinned.load(Ordering::SeqCst) && !state.capturing.load(Ordering::SeqCst) {
                    let _ = window.hide();
                }
            }
            _ => {}
        })
        .invoke_handler(tauri::generate_handler![
            prepare,
            translate,
            cancel,
            settings,
            shortcut_status,
            save_settings,
            test_connection,
            vocabulary,
            save_word,
            delete_word,
            transfer_vocabulary,
            pin,
            hide,
            copy,
            speak
        ])
        .run(tauri::generate_context!())
        .expect("Glint 启动失败");
}
