Func _get_YouTube_Videos($_yt_query, $_max_results, $_yt_api_key)
	$_yt_query = StringReplace($_yt_query, " ", "+")
	$_yt_query = 'https://www.googleapis.com/youtube/v3/search?part=snippet&maxResults='&$_max_results&'&order=viewCount&q='&$_yt_query&'&type=video&fields=items(id%2Csnippet)&key='&$_yt_api_key
	$yt_results = _INetGetSource($_yt_query)
	$yt_data = Jsmn_Decode($yt_results)
	$yt_item_array = Jsmn_ObjTo2DArray($yt_data)
	$item_count = UBound($yt_item_array[1][1]) - 1

	Dim $yt_videos[$item_count+1][3]
	$item_array = $yt_item_array[1][1]
	For $item = 0 To UBound($item_array) - 1
		$item_info = $item_array[$item]

		;get the id and snippet from the item
		If $item_info[1][0] = "id" Then
			$item_id = $item_info[1][1]
			$item_snippet = $item_info[2][1]
		Else
			$item_id = $item_info[2][1]
			$item_snippet = $item_info[1][1]
		EndIf

		;get the video id from the id
		For $ii = 1 To UBound($item_id) - 1
			If $item_id[$ii][0] = "videoId" Then
				$item_video_id = $item_id[$ii][1]
				ExitLoop
			EndIf
		Next

		;get the video title from the snippet
		For $ii = 1 To UBound($item_snippet) - 1
			If $item_snippet[$ii][0] = "description" Then
				$item_video_description = $item_snippet[$ii][1]
			ElseIf $item_snippet[$ii][0] = "thumbnails" Then
				$item_thumbnails = $item_snippet[$ii][1]
			EndIf
		Next

		;get the thumbnail
		For $ii = 1 To UBound($item_thumbnails) - 1
			If $item_thumbnails[$ii][0] = "default" Then ;(default, medium, high)
				$item_thumbnail = $item_thumbnails[$ii][1]
				ExitLoop
			EndIf
		Next
		For $ii = 1 To UBound($item_thumbnail) - 1
			If $item_thumbnail[$ii][0] = "url" Then ;(default, medium, high)
				$item_thumbnail = $item_thumbnail[$ii][1]
				ExitLoop
			EndIf
		Next

		$yt_videos[$item][0] = $item_video_id
		$yt_videos[$item][1] = $item_video_description
		$yt_videos[$item][2] = $item_thumbnail
	Next

	Return $yt_videos
EndFunc