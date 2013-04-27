#AutoIt3Wrapper_UseX64=N

#NoTrayIcon

#cs
Resources:
    Internet Assigned Number Authority - all Content-Types: http://www.iana.org/assignments/media-types/
    World Wide Web Consortium - An overview of the HTTP protocol: http://www.w3.org/Protocols/

Credits:
    Manadar for starting on the webserver.
    Alek for adding POST and some fixes
    Creator for providing the "application/octet-stream" MIME type.
#ce

;~ #include <AutoItErrorHandler.au3>
#include <Misc.au3> ; Only used for _Iif
#include <Array.au3>
#include <Date.au3>
#Include <GDIPlus.au3>
#include <GUIConstantsEx.au3>
#Include <WindowsConstants.au3>
#include <File.au3>
#include <IE.au3> ;used for IE COM interface
#include <Inet.au3> ;used to quickly download source JSON

#include <qr_code.au3> ;customized QR Code creation
#include <youtube.au3> ;custom UDF for youtube integration
#Include <JSMN.au3> ;used to parse JSON

_process_kill('youtube_jukebox.exe')
_process_kill('iexplore.exe')

$jukebox_settings = "jukebox-settings.ini"

Global $oMyError = ObjEvent("AutoIt.Error", "ErrFunc")

Global $userPeak = False

; // OPTIONS HERE //
Global Const $_MAX_SEARCH_RESULTS = Int(IniRead($jukebox_settings, "YouTube", "SearchMax", "50"))
Global Const $_MAX_PER_USER = Int(IniRead($jukebox_settings, "YouTube", "PerUserMax", "10"))
Global Const $_MAX_PER_USER_IN_A_ROW = Int(IniRead($jukebox_settings, "YouTube", "UserInARowMax", "3"))
Global Const $_YOUTUBE_API_KEY = IniRead($jukebox_settings, "YouTube", "APIKey", "YOUR YOUTUBE API KEY") ;get it here: http://code.google.com/apis/youtube/dashboard/
Global Const $_MAX_QUEUE_LENGTH = Int(IniRead($jukebox_settings, "YouTube", "QueueLength", "100"))

Global Const $_PASSWORD = IniRead($jukebox_settings, "Server", "Password", "pass")
Global Const $_PORT = Int(IniRead($jukebox_settings, "Server", "Socket", "8990"))
Global Const $_MAX_USERS = Int(IniRead($jukebox_settings, "Server", "UserMax", "200"))
Global Const $_IP_LOCAL = StringUpper(IniRead($jukebox_settings, "Server", "Local", "YES"))

Global $yt_state_file = 'youtube_state.ini'
Global $yt_video_file = 'youtube_video.ini'
Global $yt_state_file_time_check = -1
Global $yt_state_file_time = -1
Global $yt_state = -9
Global $last_played_video = ''

Global $video_array[$_MAX_QUEUE_LENGTH]
Global $video_history[100]

Local $sRootDir = @ScriptDir & "\www" ; The absolute path to the root directory of the server.
Local $sIP = @IPAddress1 ; ip address as defined by AutoIt

Global Const $sServerAddress = "http://" & $sIP & ":" & $_PORT & "/"
Local $iMaxUsers = $_MAX_USERS ; Maximum number of users who can simultaneously get/post
Local $sServerName = "YouTube Jukebox (" & @OSVersion & ") AutoIt " & @AutoItVersion
; // END OF OPTIONS //

Local $aSocket[$iMaxUsers] ; Creates an array to store all the possible users
Local $sBuffer[$iMaxUsers] ; All these users have buffers when sending/receiving, so we need a place to store those

Global $oIE
Global $curMDN
Global $curSocket

Global $yt_users[$iMaxUsers]

For $x = 0 to UBound($aSocket)-1 ; Fills the entire socket array with -1 integers, so that the server knows they are empty.
    $aSocket[$x] = -1
Next

TCPStartup() ; AutoIt needs to initialize the TCP functions

$iMainSocket = TCPListen($sIP,$_PORT) ;create main listening socket
If @error Then ; if you fail creating a socket, exit the application
    MsgBox(0x20, "AutoIt Webserver", "Unable to create a socket on port " & $_PORT & ".") ; notifies the user that the HTTP server will not run
    Exit ; if your server is part of a GUI that has nothing to do with the server, you'll need to remove the Exit keyword and notify the user that the HTTP server will not work.
EndIf

If $_IP_LOCAL = "YES" Then
	Local $sFinalIP = @IPAddress1 ; ip address as defined by AutoIt
Else
	;this php simply retrieves the public ip
	Local $sFinalIP = _INetGetSource("http://colorcoded.co/youtube/public_ip.php")
	If $sFinalIP = '' Then $sFinalIP = @IPAddress1
EndIf

Global Const $sFinalServerAddress = "http://" & $sFinalIP & ":" & $_PORT & "/"

ConsoleWrite( "Server created on " & $sFinalServerAddress & "("&$sServerAddress&")" & @CRLF) ; If you're in SciTE

;the file must not be hosted locally due to a limitation of IE
_start_player("http://colorcoded.co/youtube/index.html")

AdlibRegister("_jukebox", 500)

If $_IP_LOCAL = "YES" Then
	Global $_qr_image = createQR($sServerAddress)
Else
	Global $_qr_image = createQR($sFinalServerAddress)
EndIf

SplashImageOn("",$_qr_image,600,600,-1,-1,1)

$keepAlive = TimerInit()
While 1
    $iNewSocket = TCPAccept($iMainSocket) ; Tries to accept incoming connections

    If $iNewSocket >= 0 Then ; Verifies that there actually is an incoming connection
        For $x = 0 to UBound($aSocket)-1 ; Attempts to store the incoming connection
            If $aSocket[$x] = -1 Then
                $aSocket[$x] = $iNewSocket ;store the new socket
                ExitLoop
            EndIf
        Next
    EndIf

    For $x = 0 to UBound($aSocket)-1 ; A big loop to receive data from everyone connected
        If $aSocket[$x] = -1 Then ContinueLoop ; if the socket is empty, it will continue to the next iteration, doing nothing
        $sNewData = TCPRecv($aSocket[$x],1024) ; Receives a whole lot of data if possible
        If @error Then ; Client has disconnected
            $aSocket[$x] = -1 ; Socket is freed so that a new user may join
			_remove_user($x)
            ContinueLoop ; Go to the next iteration of the loop, not really needed but looks oh so good
        ElseIf $sNewData Then ; data received
			$curSocket = $aSocket[$x]
            $sBuffer[$x] &= $sNewData ;store it in the buffer
            If StringInStr(StringStripCR($sBuffer[$x]),@LF&@LF) Then ; if the request has ended ..
                $sFirstLine = StringLeft($sBuffer[$x],StringInStr($sBuffer[$x],@LF)) ; helps to get the type of the request
                $sRequestType = StringLeft($sFirstLine,StringInStr($sFirstLine," ")-1) ; gets the type of the request
                If $sRequestType = "GET" Then ; user wants to download a file or whatever ..
                    $sRequest = StringTrimRight(StringTrimLeft($sFirstLine,4),11) ; let's see what file he actually wants
					If StringInStr(StringReplace($sRequest,"\","/"), "/.") Then ; Disallow any attempts to go back a folder
						_HTTP_SendFileNotFoundError($aSocket[$x]) ; sends back an error
					Else
						$sRequest = StringReplace($sRequest,"\","/") ; convert HTTP slashes to windows slashes, not really required because windows accepts both
						$parameters = _getParams($sRequest)

						$search_result = ''
						For $p = 0 To UBound($parameters) - 1
							If $parameters[$p][0] = "search" Then
								$search_results = _get_YouTube_Videos(StringReplace($parameters[$p][1], "+", " "), $_MAX_SEARCH_RESULTS, $_YOUTUBE_API_KEY)
								_ArrayDisplay($search_results)
								If UBound($search_results) > 0 Then
									$search_result = '<html><body style="background-color:gray;">'
									For $s = 0 To UBound($search_results) - 1
										$search_result &= '<div style="float:left"><img src="'&$search_results[$s][2]&'" /></div><div style="float:left">'&$search_results[$s][1]&'</div><br/><a href="/index.html?add='&$search_results[$s][0]&'">ADD</a><hr/><div style="clear:both">&nbsp;</div>'
									Next
									$search_result &= '</body></html>'
								EndIf
							ElseIf $parameters[$p][0] = "add" Then
								_add_video($parameters[$p][1])
							EndIf
						Next

						If $search_result <> '' Then
							$search_page = "search_result_"&$x&".html"
							$search_file = FileOpen($sRootDir & "\" & $search_page, 2)
							FileWriteLine($search_file, $search_result)
							FileClose($search_file)
							$sRequest = "/" & $search_page
						Else
							If $sRequest = "/" Or StringInStr($sRequest, "/index.html") Then ; user has requested the root
								$sRequest = "/index.html" ; instead of root we'll give him the index page
								;SplashImageOn("",$_qr_image,200,200,0,@DesktopHeight-200,1)
								SplashOff()
							EndIf
						EndIf

						If FileExists($sRootDir & "\" & $sRequest) Then ; makes sure the file that the user wants exists
							$sFileType = StringRight($sRequest,4) ; determines the file type, so that we may choose what mine type to use
							Switch $sFileType
								Case "html", ".htm", ".xml" ; in case of normal HTML files
									_HTTP_SendFile($aSocket[$x], $sRootDir & $sRequest, "text/html")
								Case ".css" ; in case of style sheets
									_HTTP_SendFile($aSocket[$x], $sRootDir & $sRequest, "text/css")
								Case ".jpg", "jpeg" ; for common images
									_HTTP_SendFile($aSocket[$x], $sRootDir & $sRequest, "image/jpeg")
								Case ".png" ; another common image format
									_HTTP_SendFile($aSocket[$x], $sRootDir & $sRequest, "image/png")
								Case Else ; this is for .exe, .zip, or anything else that is not supported is downloaded to the client using an application/octet-stream
									_HTTP_SendFile($aSocket[$x], $sRootDir & $sRequest, "application/octet-stream")
							EndSwitch
						Else
							_HTTP_SendFileNotFoundError($aSocket[$x]) ; File does not exist, so we'll send back an error..
						EndIf
					EndIf
                ElseIf $sRequestType = "POST" Then ; user has come to us with data, we need to parse that data and based on that do something special

                    $aPOST = _HTTP_GetPost($sBuffer[$x]) ; parses the post data

                    $sComment = _HTTP_POST("wintext",$aPOST) ; Like PHPs _POST, but it requires the second parameter to be the return value from _Get_Post

                    _HTTP_ConvertString($sComment) ; Needs to convert the POST HTTP string into a normal string

                    ConsoleWrite($sComment)

					$data = FileRead($sRootDir & "\template.html")
					$data = StringReplace($data, "<?au3 Replace me ?>", $sComment)

					$h = FileOpen($sRootDir & "\index.html", 2)
                    FileWrite($h, $data)
					FileClose($h)

					$h = FileOpen($sRootDir & "\clean.html", 2)
					FileWrite($h, $sComment)
					FileClose($h)

                    _HTTP_SendFile($aSocket[$x], $sRootDir & "\index.html", "text/html") ; Sends back the new file we just created
                EndIf

                $sBuffer[$x] = "" ; clears the buffer because we just used to buffer and did some actions based on them
                $aSocket[$x] = -1 ; the socket is automatically closed so we reset the socket so that we may accept new clients

            EndIf
        EndIf
    Next

    Sleep(10)
WEnd

Func _start_player($ie_url)
	ShellExecute("youtube_jukebox.exe", $ie_url)
	WinWait("YouTube Jukebox")
	Sleep(5000)
	WinActivate("YouTube Jukebox")
	WinMove("YouTube Jukebox", "", 0, 0, 600, 600, 0)
	Sleep(2000)
	MouseClick("left", 400, 400, 1, 0)
	Sleep(2000)
	Send("f")
	Sleep(1000)
EndFunc

Func _remove_user($user)
EndFunc

Func _add_video($yt_video_id)
	For $q = 0 To $_MAX_QUEUE_LENGTH - 1
		If $video_array[$q] = "" Then
			$video_array[$q] = $yt_video_id
			Return True
		EndIf
	Next
	Return False
EndFunc

Func _play_next_video()
	;_ArrayDisplay($video_array)
	If $last_played_video <> '' Then _ArrayPush($video_history, $last_played_video, 1)
	$next_video = $video_array[0]

	For $q = 0 To $_MAX_QUEUE_LENGTH - 2
		If $video_array[$q+1] <> "" Then
			_ArraySwap($video_array[$q+1], $video_array[$q])
		Else
			$video_array[$q] = ''
			ExitLoop
		EndIf
	Next

	If $next_video = '' Then
		$last_played_video = ''
		Return False
	Else
		$last_played_video = $next_video
		Return _play_video($next_video)
	EndIf
EndFunc

Func _play_video($yt_video_id)
	For $f = 1 To 5
		$yt_file = FileOpen($yt_video_file, 2)
		If $yt_file <> -1 Then
			FileWriteLine($yt_file, $yt_video_id)
			FileClose($yt_file)
			Return True
		EndIf
		Sleep(500)
	Next
	Return False
EndFunc

Func _jukebox()
	If $last_played_video = '' And $video_array[0] <> '' Then
		_play_next_video()
	EndIf

	$yt_state_file_time_check = FileGetTime($yt_state_file, 0, 1)
	If $yt_state_file_time_check <> $yt_state_file_time Then
		$yt_file = FileOpen($yt_state_file, 0)
		If $yt_file <> -1 Then
			$yt_state_file_time = $yt_state_file_time_check
			$yt_new_state = FileReadLine($yt_file)
			FileClose($yt_file)
			If $yt_new_state <> '' Then
				$yt_state = $yt_new_state
				ConsoleWrite("New state: "&$yt_state&@CRLF)
				If $yt_state = "0" Then ;video has ended
					_play_next_video()
				EndIf
			EndIf
		EndIf
	EndIf

	Return
EndFunc

Func _getParams($sRequest)
	$params = StringSplit(StringTrimLeft($sRequest, StringInStr($sRequest, "?")), "&")
	If $params[0] = 0 Then Return 1

	$paramAmt = $params[0] + 1
	Dim $parameters[$paramAmt][2]

	For $i = 1 To $paramAmt - 1
		$var = StringSplit($params[$i], "=")
		If $var[0] <> 2 Then
			Return 0
		EndIf
		$parameters[$i][0] = $var[1]
		$parameters[$i][1] = $var[2]
	Next
	_ArrayDelete($parameters, 0)

	Return $parameters
EndFunc

Func _getParamValue($parameters, $param)
	For $p = 0 To UBound($parameters) - 1
		If $parameters[$p][0] = $param Then Return $parameters[$p][1]
	Next
EndFunc

Func _HTTP_ConvertString(ByRef $sInput) ; converts any characters like %20 into space 8)
    $sInput = StringReplace($sInput, '+', ' ')
    StringReplace($sInput, '%', '')
    For $t = 0 To @extended
        $Find_Char = StringLeft( StringTrimLeft($sInput, StringInStr($sInput, '%')) ,2)
        $sInput = StringReplace($sInput, '%' & $Find_Char, Chr(Dec($Find_Char)))
    Next
EndFunc

Func _HTTP_SendHTML($hSocket, $sHTML, $sReply = "200 OK") ; sends HTML data on X socket
    _HTTP_SendData($hSocket, Binary($sHTML), "text/html", $sReply)
EndFunc

Func _HTTP_SendFile($hSocket, $sFileLoc, $sMimeType, $sReply = "200 OK") ; Sends a file back to the client on X socket, with X mime-type
    Local $hFile, $sImgBuffer, $sPacket, $a

	ConsoleWrite("Sending " & $sFileLoc & @CRLF)

    $hFile = FileOpen($sFileLoc,16)
    $bFileData = FileRead($hFile)
    FileClose($hFile)

    _HTTP_SendData($hSocket, $bFileData, $sMimeType, $sReply)
EndFunc

Func _HTTP_SendNull($hSocket)
;~ 	$sPacket = Binary("HTTP/1.1 " & $sReply & @CRLF & _
;~     "Server: " & $sServerName & @CRLF & _
;~ 	"Connection: close" & @CRLF & _
;~ 	"Content-Lenght: " & BinaryLen($bData) & @CRLF & _
;~     "Content-Type: " & $sMimeType & @CRLF & _
;~     @CRLF)
;~     TCPSend($hSocket,$sPacket) ; Send start of packet

    $sPacket = Binary(@CRLF & @CRLF) ; Finish the packet
    TCPSend($hSocket,$sPacket)

	TCPCloseSocket($hSocket)
EndFunc

Func _HTTP_SendData($hSocket, $bData, $sMimeType, $sReply = "200 OK")
	$sPacket = Binary("HTTP/1.1 " & $sReply & @CRLF & _
    "Server: " & $sServerName & @CRLF & _
	"Connection: close" & @CRLF & _
	"Content-Lenght: " & BinaryLen($bData) & @CRLF & _
    "Content-Type: " & $sMimeType & @CRLF & _
    @CRLF)
    TCPSend($hSocket,$sPacket) ; Send start of packet

    While BinaryLen($bData) ; Send data in chunks (most code by Larry)
        $a = TCPSend($hSocket, $bData) ; TCPSend returns the number of bytes sent
        $bData = BinaryMid($bData, $a+1, BinaryLen($bData)-$a)
    WEnd

    $sPacket = Binary(@CRLF & @CRLF) ; Finish the packet
    TCPSend($hSocket,$sPacket)

	TCPCloseSocket($hSocket)
EndFunc

Func _HTTP_SendFileNotFoundError($hSocket) ; Sends back a basic 404 error
	_HTTP_SendHTML($hSocket, "Error: 404 - The file you requested could not be found.")
EndFunc

Func _HTTP_GetPost($s_Buffer) ; parses incoming POST data
    Local $sTempPost, $sLen, $sPostData, $sTemp

    ; Get the lenght of the data in the POST
    $sTempPost = StringTrimLeft($s_Buffer,StringInStr($s_Buffer,"Content-Length:"))
    $sLen = StringTrimLeft($sTempPost,StringInStr($sTempPost,": "))

    ; Create the base struck
    $sPostData = StringSplit(StringRight($s_Buffer,$sLen),"&")

    Local $sReturn[$sPostData[0]+1][2]

    For $t = 1 To $sPostData[0]
        $sTemp = StringSplit($sPostData[$t],"=")
        If $sTemp[0] >= 2 Then
            $sReturn[$t][0] = $sTemp[1]
            $sReturn[$t][1] = $sTemp[2]
        EndIf
    Next

    Return $sReturn
EndFunc

Func _HTTP_Post($sName,$sArray) ; Returns a POST variable like a associative array.
    For $i = 1 to UBound($sArray)-1
        If $sArray[$i][0] = $sName Then
            Return $sArray[$i][1]
        EndIf
    Next
    Return ""
EndFunc

Func _HTTP_SendError($aSockets, $error)
	;send error
	_HTTP_SendHTML($aSockets, $error, "text/html")
	Return
EndFunc

Func ErrFunc()
$error = "Intercepted an Error !"      & @CRLF  & @CRLF & _
             "err.description is: "    & @TAB & $oMyError.description    & @CRLF & _
             "err.windescription:"     & @TAB & $oMyError.windescription & @CRLF & _
             "err.number is: "         & @TAB & hex($oMyError.number,8)  & @CRLF & _
             "err.lastdllerror is: "   & @TAB & $oMyError.lastdllerror   & @CRLF & _
             "err.scriptline is: "     & @TAB & $oMyError.scriptline     & @CRLF & _
             "err.source is: "         & @TAB & $oMyError.source         & @CRLF & _
             "err.helpfile is: "       & @TAB & $oMyError.helpfile       & @CRLF & _
             "err.helpcontext is: "    & @TAB & $oMyError.helpcontext

    Local $err = $oMyError.number
    If $err = 0 Then $err = -1

    $g_eventerror = $err  ; to check for after this function returns

	_HTTP_SendHTML($curSocket, "FATAL: " & $error)
	Exit
Endfunc

Func _process_kill($process)
	While ProcessExists($process)
		ProcessClose($process)
		Sleep(500)
	WEnd
EndFunc