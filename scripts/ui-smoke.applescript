-- Run after launching a fresh app without selecting a remote target.
-- This test never activates a remote window, writes the clipboard, or presses Send.
tell application "System Events"
    tell process "RemoteVoiceInput"
        set w to window "远程语音输入"
        set t to text area 1 of scroll area 1 of w
        if enabled of button "发送到远程  ⌘↩" of w then error "Expected no target; refusing to test"
        if value of t is not "" then error "Existing draft found; refusing to overwrite"
        set value of t to "本机输入测试 Local test 123"
        set actualText to value of t
        set value of t to ""
        if actualText is not "本机输入测试 Local test 123" then error "Native text input failed"
        return "PASS: native text input; no-target send disabled; test draft cleared"
    end tell
end tell
