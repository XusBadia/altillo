-- The Mail event handler deliberately stays plain AppleScript. Foundation runs only after
-- message properties have been resolved, in a separate script with scalar arguments.
use AppleScript version "2.7"
use scripting additions
property bridgeScriptPath : "__BRIDGE_PATH__"
property testPrefix : "ALTILLO-MAIL-SPIKE "

using terms from application "Mail"
	on perform mail action with messages incomingMessages for rule matchedRule
		my diagnostic("handler-entered")
		set processedCount to 0
		repeat with incomingMessage in incomingMessages
			if processedCount ≥ 3 then exit repeat
			set processedCount to processedCount + 1
			set currentStage to "resolve"
			try
				set targetMessage to contents of incomingMessage
				set currentStage to "subject-get"
				with timeout of 2 seconds
					tell application id "com.apple.mail" to set rawSubject to get subject of targetMessage
				end timeout
				set currentStage to "subject-coerce"
				if rawSubject is missing value then error number -1700
				set subjectText to rawSubject as text
				with timeout of 2 seconds
					tell application id "com.apple.mail"
						-- Independent gate: even applying the rule manually must not expose ordinary mail.
						if subjectText starts with testPrefix then
							my diagnostic("subject-matched")
							set currentStage to "identifier"
							set identifierText to message id of targetMessage
							set currentStage to "sender"
							set senderText to sender of targetMessage
							set currentStage to "body"
							set bodyText to content of targetMessage
							set currentStage to "date"
							set receivedTime to date received of targetMessage
							set currentStage to "age"
							set ageSeconds to (current date) - receivedTime
							if ageSeconds ≥ -30 and ageSeconds ≤ 300 then
								set currentStage to "deliver"
								set wasDelivered to my deliver(identifierText, senderText, subjectText, bodyText, ageSeconds)
								my diagnostic("delivered=" & wasDelivered)
							else
								my diagnostic("expired")
							end if
						end if
					end tell
				end timeout
			on error errorText number errorNumber
				my diagnostic(currentStage & "-error=" & errorNumber)
			end try
		end repeat
	end perform mail action with messages
end using terms from

on diagnostic(stageName)
 try
  run script (POSIX file bridgeScriptPath) with parameters {"diagnostic", stageName}
 end try
end diagnostic

on deliver(identifierText, senderText, subjectText, bodyText, ageSeconds)
 return run script (POSIX file bridgeScriptPath) with parameters {"deliver", identifierText, senderText, subjectText, bodyText, ageSeconds}
end deliver

on run arguments
 set fixtureID to "fixture@example.invalid"
 if (count of arguments) > 0 then set fixtureID to item 1 of arguments
 return run script (POSIX file bridgeScriptPath) with parameters {"fixture", fixtureID}
end run
