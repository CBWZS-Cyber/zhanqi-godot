extends SceneTree
## 诊断：为什么 LLMDecider._post_json 连不上自家云服务（同步 HTTPClient 路径）

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var url := "http://39.105.223.8:8789/llm"
	print("url = ", url)

	var host := url.replace("https://", "").replace("http://", "")
	var path := "/"
	var slash := host.find("/")
	if slash >= 0:
		path = host.substr(slash)
		host = host.substr(0, slash)
	print("解析后 host = [", host, "]  path = [", path, "]")

	for tlsdesc in ["null(明文)", "client()"]:
		var http := HTTPClient.new()
		var tls: TLSOptions = null if tlsdesc == "null(明文)" else TLSOptions.client()
		var err := http.connect_to_host(host, -1, tls)
		print("\n--- TLSOptions = ", tlsdesc, " ---")
		print("  connect_to_host 返回 = ", err, "（OK 常量 = ", OK, "）")
		var t0 := Time.get_ticks_msec()
		while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
			http.poll()
			if Time.get_ticks_msec() - t0 > 3000:
				break
			OS.delay_msec(2)
		print("  最终状态 = ", http.get_status(),
			"（CONNECTED=", HTTPClient.STATUS_CONNECTED,
			" CONNECTING=", HTTPClient.STATUS_CONNECTING,
			" RESOLVING=", HTTPClient.STATUS_RESOLVING,
			" CANT_CONNECT=", HTTPClient.STATUS_CANT_CONNECT,
			" TLS_HANDSHAKE_ERROR=", HTTPClient.STATUS_TLS_HANDSHAKE_ERROR, "）")
		if http.get_status() == HTTPClient.STATUS_CONNECTED:
			var r := http.request(HTTPClient.METHOD_POST, path,
				["Content-Type: application/json"],
				JSON.stringify({"prompt": "诊断探针：请只回复 OK"}))
			print("  request 返回 = ", r)
			var t1 := Time.get_ticks_msec()
			while true:
				http.poll()
				var st := http.get_status()
				if st == HTTPClient.STATUS_DISCONNECTED or st == HTTPClient.STATUS_BODY:
					break
				if Time.get_ticks_msec() - t1 > 20000:
					break
				OS.delay_msec(5)
			print("  响应码 = ", http.get_response_code())
			var body := PackedByteArray()
			while http.get_status() == HTTPClient.STATUS_BODY:
				http.poll()
				var c := http.read_response_body_chunk()
				if c.size() == 0:
					break
				body.append_array(c)
			print("  响应体 = ", body.get_string_from_utf8().substr(0, 300))
		http.close()

	print("\n=== 用固定端口参数再试一次（host 不含端口）===")
	var http2 := HTTPClient.new()
	var err2 := http2.connect_to_host("39.105.223.8", 8789, null)
	print("connect_to_host(\"39.105.223.8\", 8789) 返回 = ", err2)
	var t2 := Time.get_ticks_msec()
	while http2.get_status() == HTTPClient.STATUS_CONNECTING or http2.get_status() == HTTPClient.STATUS_RESOLVING:
		http2.poll()
		if Time.get_ticks_msec() - t2 > 3000:
			break
		OS.delay_msec(2)
	print("最终状态 = ", http2.get_status())
	http2.close()

	quit(0)
