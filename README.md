# Lua-BER 编码/解码库

一个高效的 BER (Basic Encoding Rules) 编码/解码库，使用 LuaJIT 的 string.buffer 实现高性能二进制数据处理。

## 特性

- ✅ 使用 LuaJIT 的 `string.buffer` 实现高性能编码
- ✅ 完整的 LDoc 注释文档
- ✅ 支持所有常用 ASN.1 类型
- ✅ 包含 SNMP 协议支持
- ✅ 全面的测试覆盖

## 支持的 ASN.1 基本类型与用法示例


| 类型               | Tag    | 编码方法                    | 解码方法                       |
| ------------------ | ------ | --------------------------- | ---------------------------    |
| INTEGER            | 0x02   | encode_integer              | decode_integer                 |
| BOOLEAN            | 0x01   | encode_boolean              | decode_boolean                 |
| BIT STRING         | 0x03   | encode_bit_string           | decode_bit_string              |
| OCTET STRING       | 0x04   | encode_octet_string         | decode_octet_string            |
| NULL               | 0x05   | encode_null                 | decode_null                    |
| OBJECT IDENTIFIER  | 0x06   | encode_oid                  | decode_oid                     |
| UTF8 STRING        | 0x0C   | encode_utf8_string          | decode_utf8_string             |
| PrintableString    | 0x13   | encode_printable_string     | decode_printable_string        |
| IA5String          | 0x16   | encode_ia5_string           | decode_ia5_string              |
| UTC TIME           | 0x17   | encode_utc_time             | decode_utc_time                |
| GeneralizedTime    | 0x18   | encode_generalized_time     | decode_generalized_time        |
| SEQUENCE           | 0x10*  | start_sequence/end_sequence | start_sequence/at_sequence_end |
| SET                | 0x11*  | start_set/end_set           | start_set/at_sequence_end      |

> *SEQUENCE/SET 的 tag_number 见接口实现，编码时需用 start_xxx/end_xxx。

### 典型用法示例

**编码 INTEGER/BOOLEAN/STRING：**

```lua
local enc = ber.new_encoder()
enc:encode_integer(42)
enc:encode_boolean(true)
enc:encode_utf8_string("hello")
local data = enc:get()
```

**解码：**

```lua
local dec = ber.new_decoder(data)
local i = dec:decode_integer()
local b = dec:decode_boolean()
local s = dec:decode_utf8_string()
```

**编码嵌套 SEQUENCE：**

```lua
local enc = ber.new_encoder()
local seq = enc:start_sequence()
seq:encode_integer(1)
seq:encode_utf8_string("abc")
enc:end_sequence(seq)
local data = enc:get()
```

**解码嵌套 SEQUENCE：**

```lua
local dec = ber.new_decoder(data)
local end_pos = dec:start_sequence()
local i = dec:decode_integer()
local s = dec:decode_utf8_string()
assert(dec:at_sequence_end(end_pos))
```

**编码 SET：**

```lua
local enc = ber.new_encoder()
local set = enc:start_set()
set:encode_integer(11)
set:encode_utf8_string("abc")
enc:end_set(set)
local data = enc:get()
```

**解码 SET：**

```lua
local dec = ber.new_decoder(data)
local set_end = dec:start_set()
local i = dec:decode_integer()
local s = dec:decode_utf8_string()
assert(dec:at_sequence_end(set_end))
```

**CHOICE/OPTIONAL/递归结构**

- 见 test.lua 单元测试中的用法示例。

---

## 健壮性与异常处理

- 解码端对非法 BER 数据（如长度越界、格式错误、内容缺失等）会抛出 Lua error，便于上层捕获。
- 建议所有解码操作用 pcall 包裹，或参考 test.lua 中 fuzz 测试用例。


## 关于 SEQUENCE 的编码与解码接口差异

### 编码端（Encoder）

- `enc:start_sequence()` 返回一个新的子编码器（子缓冲区），用于递归编码 SEQUENCE 内部的内容。
- 子编码器编码完内容后，需通过 `enc:end_sequence(seq)` 将其合并到父编码器，此时父编码器会自动写入 SEQUENCE 的 tag、length 和内容。
- 这种设计是因为 BER 编码要求长度字段必须在内容前面，只有先编码完内容才能确定长度。

**示例：**

````lua
local enc = ber.new_encoder()
local seq = enc:start_sequence()
seq:encode_integer(42)
seq:encode_octet_string("foo")
enc:end_sequence(seq)
local data = enc:get()
````

### 解码端（Decoder）

- `dec:start_sequence()` 会自动读取 SEQUENCE 的 tag 和 length，并返回序列结束位置（end_pos）。
- 用户随后可直接在主解码器上顺序解码 SEQUENCE 内部的内容，并通过 `dec:at_sequence_end(end_pos)` 判断序列是否结束。

**示例：**

````lua
local dec = ber.new_decoder(data)
local end_pos = dec:start_sequence()
while not dec:at_sequence_end(end_pos) do
    -- 顺序解码 SEQUENCE 内部内容
end
````

### 设计说明

- 编码端采用子编码器递归，是为了满足 BER 长度字段的前置要求。
- 解码端采用流式游标推进，便于顺序和嵌套结构的解码。
- 这种接口风格在业界 ASN.1/BER 库中较为常见，兼顾了灵活性和性能。

如需更高级的结构化编码接口，可自行封装或联系作者协助扩展。

---

## SNMP 协议支持

本库包含了一个完整的 SNMP (Simple Network Management Protocol) 实现，支持 SNMPv1/v2c 消息的编码和解码。

### SNMP 功能特性

- ✅ 支持 GetRequest、GetNextRequest、SetRequest、GetResponse PDU
- ✅ 支持所有标准 SNMP 数据类型（Integer、String、OID、Counter32、TimeTicks 等）
- ✅ 完整的错误处理
- ✅ OID 字符串格式化和解析工具
- ✅ 详细的使用示例和测试

### SNMP 快速开始

#### 创建 SNMP GetRequest

```lua
local snmp = require('snmp')

-- 创建一个 GetRequest 查询系统信息
local request = snmp.encode_get_request(
    snmp.VERSION_2C,     -- SNMP v2c
    "public",            -- 团体字符串
    12345,               -- 请求 ID
    {
        {1, 3, 6, 1, 2, 1, 1, 1, 0},  -- sysDescr.0
        {1, 3, 6, 1, 2, 1, 1, 5, 0}   -- sysName.0
    }
)

-- request 现在包含可以发送到 SNMP 代理的 BER 编码数据
-- 通过 UDP socket 发送: sock:sendto(request, agent_ip, 161)
```

#### 解析 SNMP 响应

```lua
-- 从网络接收到响应数据后
local response = snmp.decode_message(response_data)

print("SNMP 版本:", response.version)
print("团体字符串:", response.community)
print("请求 ID:", response.request_id)
print("错误状态:", response.error_status)

-- 遍历变量绑定
for i, vb in ipairs(response.varbinds) do
    print("OID:", snmp.format_oid(vb.oid))
    print("类型:", vb.type)
    print("值:", vb.value)
end
```

#### 创建 SNMP SetRequest

```lua
local set_request = snmp.encode_set_request(
    snmp.VERSION_2C,
    "private",
    12346,
    {
        {{1, 3, 6, 1, 2, 1, 1, 5, 0}, "string", "new-hostname"},
        {{1, 3, 6, 1, 2, 1, 1, 6, 0}, "string", "Server Room A"}
    }
)
```

### SNMP 常用 OID

| OID | 名称 | 描述 |
|-----|------|------|
| 1.3.6.1.2.1.1.1.0 | sysDescr | 系统描述 |
| 1.3.6.1.2.1.1.2.0 | sysObjectID | 系统对象标识符 |
| 1.3.6.1.2.1.1.3.0 | sysUpTime | 系统运行时间 |
| 1.3.6.1.2.1.1.4.0 | sysContact | 系统联系人 |
| 1.3.6.1.2.1.1.5.0 | sysName | 系统名称 |
| 1.3.6.1.2.1.1.6.0 | sysLocation | 系统位置 |

### SNMP 示例文件

运行示例查看更多用法：

```bash
luajit snmp_examples.lua   # SNMP 使用示例
luajit test_snmp.lua       # SNMP 测试
```

---

## 测试

运行所有测试：

```bash
luajit test.lua        # BER 编码/解码测试
luajit test_snmp.lua   # SNMP 协议测试
```

---

## 性能优化

本库使用 LuaJIT 的 `string.buffer` 来实现高性能的二进制数据编码和解码：

- **编码器**：使用 `string.buffer` 增量构建 BER 数据，避免字符串拼接开销
- **解码器**：使用 `string.buffer` 存储输入数据，通过位置游标高效读取
- **零拷贝**：OID 和长度编码使用优化的位操作

---

## 代码质量

- ✅ 完整的 LDoc 文档注释
- ✅ 详细的参数和返回值说明
- ✅ 丰富的使用示例
- ✅ 全面的单元测试
- ✅ 错误处理和边界情况覆盖

---

## 许可证

MIT License

---

## 贡献

欢迎提交 Issue 和 Pull Request！
