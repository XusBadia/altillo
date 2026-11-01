use AppleScript version "2.7"
use framework "Foundation"
use scripting additions

-- The runner renders these two paths before compiling. They contain no mail data.
property helperPath : "__HELPER_PATH__"
property socketPath : "__SOCKET_PATH__"
property tracePath : "__TRACE_PATH__"
property testPrefix : "ALTILLO-MAIL-SPIKE "

on diagnostic(stageName)
	try
		if not (current application's NSFileManager's defaultManager()'s fileExistsAtPath:tracePath) as boolean then return
		set textValue to current application's NSString's stringWithString:(stageName & linefeed)
		set bytes to textValue's dataUsingEncoding:(current application's NSUTF8StringEncoding)
		bytes's writeToFile:tracePath atomically:true
	end try
end diagnostic

on shortText(inputText, maximumLength)
	if (length of inputText) > maximumLength then return text 1 thru maximumLength of inputText
	return inputText
end shortText

on deliver(identifierText, senderText, subjectText, bodyText, ageSeconds)
	if not (current application's NSFileManager's defaultManager()'s fileExistsAtPath:socketPath) as boolean then return false
	-- Local variables only: Mail must never save the last message in script properties.
	set payload to current application's NSMutableDictionary's dictionary()
	payload's setObject:1 forKey:"version"
	payload's setObject:identifierText forKey:"messageID"
	payload's setObject:(my shortText(senderText, 200)) forKey:"sender"
	payload's setObject:(my shortText(subjectText, 250)) forKey:"subject"
	payload's setObject:(my shortText(bodyText, 1024)) forKey:"body"
	-- NSDate instances bridge to AppleScript dates; use the class clock to keep an epoch number.
	set timestamp to (current application's NSDate's timeIntervalSinceReferenceDate()) + 978307200 - ageSeconds
	payload's setObject:timestamp forKey:"receivedAt"
	set {jsonData, jsonError} to current application's NSJSONSerialization's dataWithJSONObject:payload options:0 |error|:(reference)
	if jsonData is missing value then return false
	-- Fit inside the pipe; don't write arbitrarily large messages or attachments.
	if (jsonData's |length|() as integer) > 8192 then return false
	set inputPipe to current application's NSPipe's pipe()
	set writer to inputPipe's fileHandleForWriting()
	set task to current application's NSTask's alloc()'s init()
	task's setLaunchPath:helperPath
	task's setArguments:{"send", "--socket", socketPath}
	task's setStandardInput:inputPipe
	task's setStandardOutput:(current application's NSFileHandle's fileHandleWithNullDevice())
	task's setStandardError:(current application's NSFileHandle's fileHandleWithNullDevice())
	set {launched, launchError} to task's launchAndReturnError:(reference)
	if not (launched as boolean) then return false
	try
		writer's writeData:jsonData
		writer's closeFile()
		set deadline to (current date) + 3
		repeat while (task's isRunning() as boolean)
			if (current date) ≥ deadline then
				task's terminate()
				return false
			end if
			delay 0.05
		end repeat
		return (task's terminationStatus() as integer) = 0
	on error
		try
			writer's closeFile()
		end try
		if task's isRunning() as boolean then task's terminate()
		return false
	end try
end deliver

on run arguments
 if (count of arguments) > 0 then
  if item 1 of arguments is "diagnostic" then
   my diagnostic(item 2 of arguments)
   return true
  end if
  if item 1 of arguments is "deliver" then return my deliver(item 2 of arguments, item 3 of arguments, item 4 of arguments, item 5 of arguments, item 6 of arguments)
 end if
 set fixtureID to "fixture@example.invalid"
 if (count of arguments) > 1 then set fixtureID to item 2 of arguments
 return my deliver(fixtureID, "Altillo · prueba local", testPrefix & "Acceso de prueba", "Tu código de acceso: 482913" & linefeed & "https://example.invalid/login?token=synthetic", 0)
end run
