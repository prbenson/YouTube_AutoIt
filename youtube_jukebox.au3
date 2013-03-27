#include <IE.au3>

Global $g_eventerror = 0  ; to be checked to know if com error occurs. Must be reset after handling.

$oMyError = ObjEvent("AutoIt.Error","MyErrFunc") ; Install a custom error handler

$oIE = _IECreate($ie_url)

$yt_state_old = -9
$playing = False

While 1
	$yt_state = IEEval($oIE, "getState();")
	If $yt_state <> False Then
		If $yt_state <> $yt_state_old Then
			$yt_file = FileOpen($yt_state_file, 2)
			If $yt_file <> -1 Then
				$yt_state_old = $yt_state
				If $yt_state = "0" Then
					;IEEval($oIE, "hideplayer();")
				EndIf
				ConsoleWrite("New State: "&$yt_state&@CRLF)
				FileWriteLine($yt_file, $yt_state)
				FileClose($yt_file)
			EndIf
		EndIf
	EndIf

	$yt_video_file_time_check = FileGetTime($yt_video_file, 0, 1)
	If $yt_video_file_time_check <> $yt_video_file_time Then
		$yt_file = FileOpen($yt_video_file, 0)
		If $yt_file <> -1 Then
			$yt_video_file_time = $yt_video_file_time_check
			$yt_video = FileReadLine($yt_file)
			FileClose($yt_file)
			If $yt_video <> '' Then
				ConsoleWrite("New Video: "&$yt_video&@CRLF)
				IEEval($oIE, "play('"&$yt_video&"');")

			EndIf
		EndIf
	EndIf

	Sleep(500)
WEnd

Func IEEval($o_object, $s_eval)
	$s_eval_return = $o_object.document.parentwindow.eval($s_eval)
	If $g_eventerror Then
		$g_eventerror = 0
		Return False
	Else
		Return $s_eval_return
	EndIf
EndFunc   ;==>IEEval

; This is my custom error handler
Func MyErrFunc()
   $HexNumber=hex($oMyError.number,8)
   $error_message = "We intercepted a COM Error !" & @CRLF & _
                "Number is: " & $HexNumber & @CRLF & _
                "Windescription is: " & $oMyError.windescription & @CRLF & @CRLF
   ConsoleWrite($error_message)
	;MsgBox(0, "", $error_message)
   $g_eventerror = 1 ; something to check for when this function returns
Endfunc
