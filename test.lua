local ber = require('ber')

local function assert_eq(a, b, msg)
    if a ~= b then
        error((msg or "") .. string.format("\n  expected: %s\n  actual:   %s", tostring(b), tostring(a)))
    end
end

-- 整数编码/解码测试
local values = {0, 1, -1, 127, -128, 128, -129, 65535, -65536, 2^31-1, -2^31}
for _, v in ipairs(values) do
    local encoded = ber.encode_integer(v)

    local decoded = ber.decode_integer(encoded)
    assert_eq(decoded, v, "BER integer encode/decode failed for " .. tostring(v))
end


-- OID 编码/解码测试
local oids = {
    {1, 3, 6, 1, 4, 1},
    {2, 5, 4, 3},
    {1, 2, 840, 113549, 1, 1, 5},
}
for _, oid in ipairs(oids) do
    local encoded = ber.encode_oid(oid)
    local decoded = ber.decode_oid(encoded)
    assert(#decoded == #oid, "BER OID decode length mismatch")
    for i = 1, #oid do
        assert_eq(decoded[i], oid[i], "BER OID encode/decode failed at index " .. i)
    end
end

-- OCTET STRING 编码/解码测试
local octets = {"", "abc", "\0\1\2\255"}
for _, s in ipairs(octets) do
    local enc = ber.new_encoder()
    enc:encode_octet_string(s)
    local encoded = enc:get()
    local dec = ber.new_decoder(encoded)
    local decoded = dec:decode_octet_string()
    assert_eq(decoded, s, "BER octet string encode/decode failed for " .. tostring(s))
end

-- NULL 类型测试
do
    local enc = ber.new_encoder()
    enc:encode_null()
    local encoded = enc:get()
    local dec = ber.new_decoder(encoded)
    assert(dec:decode_null() == true, "BER NULL decode failed")
end

-- 嵌套 SEQUENCE 测试
do
    local enc = ber.new_encoder()
    local seq1 = enc:start_sequence()
    seq1:encode_integer(123)
    seq1:encode_octet_string("foo")
    local seq2 = seq1:start_sequence()
    seq2:encode_integer(-456)
    seq1:end_sequence(seq2)
    enc:end_sequence(seq1)
    local encoded = enc:get()

    local dec = ber.new_decoder(encoded)
    local end1 = dec:start_sequence()
    assert_eq(dec:decode_integer(), 123, "Nested SEQUENCE integer failed")
    assert_eq(dec:decode_octet_string(), "foo", "Nested SEQUENCE string failed")
    local end2 = dec:start_sequence()
    assert_eq(dec:decode_integer(), -456, "Nested SEQUENCE inner integer failed")
    assert(dec:at_sequence_end(end2), "Nested SEQUENCE inner end failed")
    assert(dec:at_sequence_end(end1), "Nested SEQUENCE outer end failed")
end



-- BOOLEAN 测试
local enc = ber.new_encoder()
enc:encode_boolean(true)
local dec = ber.new_decoder(enc:get())
assert(dec:decode_boolean() == true, "BER BOOLEAN true failed")
enc:reset()
enc:encode_boolean(false)
dec = ber.new_decoder(enc:get())
assert(dec:decode_boolean() == false, "BER BOOLEAN false failed")

-- BIT STRING 测试
enc:reset()
enc:encode_bit_string("\xF0", 4)
dec = ber.new_decoder(enc:get())
local data, unused = dec:decode_bit_string()
assert(data == "\xF0" and unused == 4, "BER BIT STRING failed")

-- UTF8 STRING 测试
enc:reset()
enc:encode_utf8_string("你好")
dec = ber.new_decoder(enc:get())
assert(dec:decode_utf8_string() == "你好", "BER UTF8 STRING failed")

-- PrintableString 测试
enc:reset()
enc:encode_printable_string("Hello123")
dec = ber.new_decoder(enc:get())
assert(dec:decode_printable_string() == "Hello123", "BER PrintableString failed")

-- IA5String 测试
enc:reset()
enc:encode_ia5_string("test@abc.com")
dec = ber.new_decoder(enc:get())
assert(dec:decode_ia5_string() == "test@abc.com", "BER IA5String failed")

-- UTC TIME 测试
enc:reset()
enc:encode_utc_time("230101120000Z")
dec = ber.new_decoder(enc:get())
assert(dec:decode_utc_time() == "230101120000Z", "BER UTC TIME failed")

-- GeneralizedTime 测试
enc:reset()
enc:encode_generalized_time("20231103120000Z")
dec = ber.new_decoder(enc:get())
assert(dec:decode_generalized_time() == "20231103120000Z", "BER GeneralizedTime failed")

-- SET 测试
enc:reset()
local set = enc:start_set()
set:encode_integer(11)
set:encode_utf8_string("abc")
enc:end_set(set)
dec = ber.new_decoder(enc:get())
local set_end = dec:start_set()
assert_eq(dec:decode_integer(), 11, "BER SET integer failed")
assert_eq(dec:decode_utf8_string(), "abc", "BER SET utf8_string failed")
assert(dec:at_sequence_end(set_end), "BER SET at end failed")

-- CHOICE 测试（int 或 string）
enc:reset()
enc:encode_integer(99)
dec = ber.new_decoder(enc:get())
local tag_info = dec:decode_tag()
dec:set_position(dec:get_position() - 1)
if tag_info.tag == ber.INTEGER then
    assert_eq(dec:decode_integer(), 99, "BER CHOICE integer failed")
else
    error("BER CHOICE: unexpected tag")
end
enc:reset()
enc:encode_utf8_string("choice")
dec = ber.new_decoder(enc:get())
tag_info = dec:decode_tag()
dec:set_position(dec:get_position() - 1)
if tag_info.tag == ber.INTEGER then
    error("BER CHOICE: unexpected tag")
else
    assert_eq(dec:decode_utf8_string(), "choice", "BER CHOICE utf8_string failed")
end

-- OPTIONAL/DEFAULT 测试
enc:reset()
local seq = enc:start_sequence()
seq:encode_integer(1) -- 必选
-- 可选字段不写入
enc:end_sequence(seq)
dec = ber.new_decoder(enc:get())
local end_pos = dec:start_sequence()
local v1 = dec:decode_integer()
local v2 = nil
if not dec:at_sequence_end(end_pos) then
    v2 = dec:decode_utf8_string()
end
assert_eq(v1, 1, "BER OPTIONAL required field failed")
assert(v2 == nil, "BER OPTIONAL missing field failed")

-- 嵌套递归结构测试
local function encode_node(enc, node)
    local seq = enc:start_sequence()
    seq:encode_integer(node.value)
    if node.child then
        encode_node(seq, node.child)
    end
    enc:end_sequence(seq)
end
local function decode_node(dec)
    local end_pos = dec:start_sequence()
    local value = dec:decode_integer()
    local child = nil
    if not dec:at_sequence_end(end_pos) then
        child = decode_node(dec)
    end
    return {value = value, child = child}
end
enc:reset()
local node = {value=1, child={value=2, child={value=3}}}
encode_node(enc, node)
dec = ber.new_decoder(enc:get())
local node2 = decode_node(dec)
assert(node2.value == 1 and node2.child.value == 2 and node2.child.child.value == 3, "BER recursive structure failed")

-- fuzz/随机非法数据健壮性测试
local function expect_error(fn, msg)
    local ok, err = pcall(fn)
    assert(not ok and (err:find(msg) or err:find("unexpected end of data")), "Expected error: "..msg.." but got: "..tostring(err))
end
expect_error(function() ber.new_decoder("\x02\xFF"):decode_integer() end, "invalid INTEGER length")
expect_error(function() ber.new_decoder("\x05\x01\x00"):decode_null() end, "zero length")
expect_error(function() ber.new_decoder("\x04\xFF"):decode_octet_string() end, "invalid OCTET_STRING length")
expect_error(function() ber.new_decoder("\x06\xFF"):decode_oid() end, "invalid OID length")
expect_error(function() ber.new_decoder("\x02"):decode_integer() end, "unexpected end of data")
expect_error(function() ber.new_decoder(""):decode_integer() end, "unexpected end of data")

print("All BER encode/decode tests passed.")





