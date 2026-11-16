-- Keeps an existing compose draft only in this script's memory during an update.
on run argv
    if (count of argv) is not 2 then error "Expected source app and installed app paths"
    set sourceApp to item 1 of argv
    set installedApp to item 2 of argv
    set savedDraft to ""
    set oldAppStopped to false
    try
        tell application "System Events"
            if exists process "RemoteVoiceInput" then
                tell process "RemoteVoiceInput"
                    if not (exists window "远程语音输入") then
                        click menu item "打开输入窗（先选远程输入框）" of menu 1 of menu bar item 1 of menu bar 2
                    end if
                    if not (exists window "远程语音输入") then error "Open the existing compose window before updating"
                    set savedDraft to value of text area 1 of scroll area 1 of window "远程语音输入"
                    if savedDraft is missing value then set savedDraft to ""
                end tell
            end if
        end tell
        tell application id "local.lizzer.RemoteVoiceInput" to quit
        repeat 50 times
            tell application "System Events" to set stillRunning to exists process "RemoteVoiceInput"
            if not stillRunning then exit repeat
            delay 0.1
        end repeat
        if stillRunning then error "Existing app did not quit; installation cancelled"
        set oldAppStopped to true
        do shell script "/usr/bin/ditto " & quoted form of sourceApp & " " & quoted form of installedApp
        do shell script "/usr/bin/open " & quoted form of installedApp
        set ready to false
        repeat 100 times
            tell application "System Events"
                if exists process "RemoteVoiceInput" then
                    tell process "RemoteVoiceInput" to set ready to exists window "远程语音输入"
                end if
            end tell
            if ready then exit repeat
            delay 0.1
        end repeat
        if not ready then error "Updated compose window did not open"
        tell application "System Events"
            tell process "RemoteVoiceInput"
                set t to text area 1 of scroll area 1 of window "远程语音输入"
                set value of t to savedDraft
                set actualDraft to value of t
                if actualDraft is missing value then set actualDraft to ""
                if actualDraft is not savedDraft then error "Draft restoration failed"
            end tell
        end tell
        return "Installed; draft preserved in memory (" & (length of savedDraft) & " characters); clipboard unchanged"
    on error errorMessage number errorNumber
        if oldAppStopped and savedDraft is not "" then
            display dialog "更新未完成。你的原草稿保留在下方，请先保留文字再关闭此对话框。" default answer savedDraft buttons {"好"} default button 1
        end if
        error errorMessage number errorNumber
    end try
end run
