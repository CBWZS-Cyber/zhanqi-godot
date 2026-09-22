class_name AICfg
extends RefCounted
## 豆包/火山方舟 LLM 内置配置
## API Key 以「XOR + base64」混淆后存于 res://scripts/ai/ai_key.bin（随包分发），
## 运行时解密使用 —— 注意：客户端混淆可防“一眼抄走”，无法防抓包/内存（平台物理限制）。
## 若 ai_key.bin 缺失或解密异常 → key 为空，调用方应回退本地 AI。

const DEFAULT_BASE_URL := "https://ark.cn-beijing.volces.com/api/v3/responses"
const DEFAULT_MODEL := "doubao-seed-evolving"
const _SECRET := "ZHANQI-ARK-2026-0905-XOR"

static func _key_bytes() -> PackedByteArray:
	var f := FileAccess.open("res://scripts/ai/ai_key.bin", FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var enc := f.get_buffer(f.get_length())
	f.close()
	var sec := _SECRET.to_utf8_buffer()
	var dec := PackedByteArray()
	dec.resize(enc.size())
	for i in range(enc.size()):
		dec[i] = enc[i] ^ sec[i % sec.size()]
	return dec

## 返回解密后的明文 API Key；异常返回 ""
static func api_key() -> String:
	var dec := _key_bytes()
	if dec.is_empty():
		return ""
	var b64 := dec.get_string_from_ascii()
	if b64.strip_edges() == "":
		return ""
	var parsed: Variant = Marshalls.base64_to_utf8(b64)
	if parsed == null:
		return ""
	return str(parsed)

## LLM 是否可用的便捷判断（key 非空即视为可用）
static func ready() -> bool:
	return api_key() != ""
