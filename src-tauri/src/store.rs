use crate::dictionary::{Card, normalize};
use rusqlite::{Connection, OptionalExtension, params};
use serde::{Deserialize, Serialize};

#[derive(Clone, Serialize, Deserialize)]
pub struct Settings {
    pub endpoint: String,
    pub model: String,
    pub shortcuts: [String; 3],
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            endpoint: "https://api.deepseek.com".into(),
            model: "deepseek-flash".into(),
            shortcuts: ["Alt+KeyD".into(), "Alt+KeyA".into(), "Alt+KeyS".into()],
        }
    }
}

#[derive(Clone, Serialize, Deserialize)]
pub struct SavedWord {
    pub id: String,
    pub card: Card,
    pub source_language: String,
    pub target_language: String,
    pub contexts: Vec<String>,
    pub saved_at: u64,
}

pub fn initialize(db: &Connection) -> Result<(), String> {
    db.execute_batch("CREATE TABLE IF NOT EXISTS settings (id INTEGER PRIMARY KEY CHECK(id=1), value TEXT NOT NULL); CREATE TABLE IF NOT EXISTS vocabulary (id TEXT PRIMARY KEY, value TEXT NOT NULL);").map_err(|e| e.to_string())
}

pub fn settings(db: &Connection) -> Result<Settings, String> {
    let value: Option<String> = db
        .query_row("SELECT value FROM settings WHERE id=1", [], |row| {
            row.get(0)
        })
        .optional()
        .map_err(|e| e.to_string())?;
    value
        .map(|json| serde_json::from_str(&json).map_err(|e| e.to_string()))
        .unwrap_or_else(|| Ok(Settings::default()))
}

pub fn save_settings(db: &Connection, settings: &Settings) -> Result<(), String> {
    db.execute(
        "INSERT INTO settings VALUES(1,?) ON CONFLICT(id) DO UPDATE SET value=excluded.value",
        [serde_json::to_string(settings).map_err(|e| e.to_string())?],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn vocabulary(db: &Connection) -> Result<Vec<SavedWord>, String> {
    let mut statement = db
        .prepare("SELECT value FROM vocabulary ORDER BY rowid DESC")
        .map_err(|e| e.to_string())?;
    statement
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(|e| e.to_string())?
        .map(|row| {
            serde_json::from_str(&row.map_err(|e| e.to_string())?).map_err(|e| e.to_string())
        })
        .collect()
}

pub fn save_word(db: &Connection, mut word: SavedWord) -> Result<(), String> {
    if word.card.original.trim().is_empty() || word.card.entry.word.trim().is_empty() {
        return Err("收藏条目缺少原词或词头".into());
    }
    word.id = serde_json::to_string(&(
        &word.source_language,
        &word.target_language,
        normalize(&word.card.entry.word),
        if word.card.confirmed {
            String::new()
        } else {
            normalize(&word.card.original)
        },
    ))
    .map_err(|e| e.to_string())?;
    let existing: Option<String> = db
        .query_row(
            "SELECT value FROM vocabulary WHERE id=?",
            [&word.id],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| e.to_string())?;
    if let Some(json) = existing {
        let previous: SavedWord = serde_json::from_str(&json).map_err(|e| e.to_string())?;
        word.saved_at = previous.saved_at;
        for context in previous.contexts {
            if !word.contexts.contains(&context) {
                word.contexts.push(context);
            }
        }
    }
    word.contexts.retain(|context| !context.trim().is_empty());
    word.contexts.sort();
    word.contexts.dedup();
    db.execute(
        "INSERT INTO vocabulary VALUES(?,?) ON CONFLICT(id) DO UPDATE SET value=excluded.value",
        params![
            word.id,
            serde_json::to_string(&word).map_err(|e| e.to_string())?
        ],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dictionary::Entry;
    #[test]
    fn persistence_keeps_independent_meanings_and_appends_context() {
        let db = Connection::open_in_memory().unwrap();
        initialize(&db).unwrap();
        let mut word = SavedWord {
            id: String::new(),
            card: Card {
                original: "goods".into(),
                entry: Entry {
                    word: "goods".into(),
                    phonetic: String::new(),
                    translation: "货物".into(),
                    definition: String::new(),
                },
                relations: vec![],
                confirmed: false,
                source: "ECDICT".into(),
            },
            source_language: "en".into(),
            target_language: "zh".into(),
            contexts: vec!["deliver goods".into()],
            saved_at: 1,
        };
        save_word(&db, word.clone()).unwrap();
        word.contexts = vec!["buy goods".into()];
        save_word(&db, word.clone()).unwrap();
        assert_eq!(vocabulary(&db).unwrap()[0].contexts.len(), 2);
        word.card.original = "good".into();
        word.card.entry.word = "good".into();
        save_word(&db, word).unwrap();
        assert_eq!(vocabulary(&db).unwrap().len(), 2);
    }
}
