use std::io::Write;
use std::process::{Command, Stdio};
use tauri::{AppHandle, Manager};

pub fn native(app: &AppHandle, action: &str, input: Option<&str>) -> Result<String, String> {
    let path = app
        .path()
        .resource_dir()
        .map_err(|e| e.to_string())?
        .join("resources/glint-native");
    let mut command = Command::new(path);
    command.arg(action);
    if action == "restore" {
        command.arg(input.unwrap_or("0"));
    }
    let mut child = command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| e.to_string())?;
    if action != "restore"
        && let Some(input) = input
    {
        child
            .stdin
            .take()
            .unwrap()
            .write_all(input.as_bytes())
            .map_err(|e| e.to_string())?;
    }
    drop(child.stdin.take());
    let output = child.wait_with_output().map_err(|e| e.to_string())?;
    if output.status.code() == Some(2) {
        return Err("已取消截图".into());
    }
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_string());
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}
