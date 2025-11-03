#!/usr/bin/env luajit

local snmp = require('snmp')
local ber = require('ber')

local function assert_eq(a, b, msg)
    if a ~= b then
        error((msg or "") .. string.format("\n  expected: %s\n  actual:   %s", tostring(b), tostring(a)))
    end
end

local function assert_table_eq(a, b, msg)
    if #a ~= #b then
        error((msg or "Table length mismatch") .. string.format("\n  expected length: %d\n  actual length:   %d", #b, #a))
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            error((msg or "Table element mismatch at index " .. i) .. string.format("\n  expected: %s\n  actual:   %s", tostring(b[i]), tostring(a[i])))
        end
    end
end

print("Testing SNMP library...")

-- 测试 1: 编码和解码 GetRequest
print("Test 1: GetRequest encode/decode")
local get_request = snmp.encode_get_request(
    snmp.VERSION_2C,
    "public",
    12345,
    {
        {1, 3, 6, 1, 2, 1, 1, 1, 0},  -- sysDescr.0
        {1, 3, 6, 1, 2, 1, 1, 5, 0}   -- sysName.0
    }
)

-- 验证编码成功
assert(#get_request > 0, "GetRequest encoding failed")
print("  GetRequest encoded successfully (" .. #get_request .. " bytes)")

-- 测试 2: 编码和解码 GetNextRequest
print("Test 2: GetNextRequest encode/decode")
local get_next = snmp.encode_get_next_request(
    snmp.VERSION_2C,
    "public",
    12346,
    {
        {1, 3, 6, 1, 2, 1, 1}
    }
)

assert(#get_next > 0, "GetNextRequest encoding failed")
print("  GetNextRequest encoded successfully (" .. #get_next .. " bytes)")

-- 测试 3: 编码和解码 SetRequest
print("Test 3: SetRequest encode/decode")
local set_request = snmp.encode_set_request(
    snmp.VERSION_2C,
    "private",
    12347,
    {
        {{1, 3, 6, 1, 2, 1, 1, 5, 0}, "string", "NewHostName"},
        {{1, 3, 6, 1, 2, 1, 1, 6, 0}, "string", "Building 42"}
    }
)

assert(#set_request > 0, "SetRequest encoding failed")
print("  SetRequest encoded successfully (" .. #set_request .. " bytes)")

-- 测试 4: 编码 GetResponse 并解码
print("Test 4: GetResponse encode and decode")
local get_response = snmp.encode_get_response(
    snmp.VERSION_2C,
    "public",
    12345,
    snmp.NO_ERROR,
    0,
    {
        {{1, 3, 6, 1, 2, 1, 1, 1, 0}, "string", "Linux server 5.4.0"},
        {{1, 3, 6, 1, 2, 1, 1, 5, 0}, "string", "myhost"}
    }
)

assert(#get_response > 0, "GetResponse encoding failed")
print("  GetResponse encoded successfully (" .. #get_response .. " bytes)")

-- 解码 GetResponse
local decoded = snmp.decode_message(get_response)
assert_eq(decoded.version, snmp.VERSION_2C, "Version mismatch")
assert_eq(decoded.community, "public", "Community mismatch")
assert_eq(decoded.pdu_type, 2, "PDU type mismatch (expected GetResponse)")
assert_eq(decoded.request_id, 12345, "Request ID mismatch")
assert_eq(decoded.error_status, snmp.NO_ERROR, "Error status mismatch")
assert_eq(decoded.error_index, 0, "Error index mismatch")
assert_eq(#decoded.varbinds, 2, "VarBind count mismatch")

assert_table_eq(decoded.varbinds[1].oid, {1, 3, 6, 1, 2, 1, 1, 1, 0}, "First OID mismatch")
assert_eq(decoded.varbinds[1].type, "string", "First value type mismatch")
assert_eq(decoded.varbinds[1].value, "Linux server 5.4.0", "First value mismatch")

assert_table_eq(decoded.varbinds[2].oid, {1, 3, 6, 1, 2, 1, 1, 5, 0}, "Second OID mismatch")
assert_eq(decoded.varbinds[2].type, "string", "Second value type mismatch")
assert_eq(decoded.varbinds[2].value, "myhost", "Second value mismatch")

print("  GetResponse decoded successfully")

-- 测试 5: OID 格式化和解析
print("Test 5: OID formatting and parsing")
local oid = {1, 3, 6, 1, 2, 1, 1, 1, 0}
local oid_str = snmp.format_oid(oid)
assert_eq(oid_str, "1.3.6.1.2.1.1.1.0", "OID formatting failed")

local parsed_oid = snmp.parse_oid("1.3.6.1.2.1.1.5.0")
assert_table_eq(parsed_oid, {1, 3, 6, 1, 2, 1, 1, 5, 0}, "OID parsing failed")
print("  OID format/parse successful")

-- 测试 6: 带整数值的响应
print("Test 6: Response with integer values")
local response_with_int = snmp.encode_get_response(
    snmp.VERSION_2C,
    "public",
    99999,
    snmp.NO_ERROR,
    0,
    {
        {{1, 3, 6, 1, 2, 1, 1, 3, 0}, "integer", 12345678},
        {{1, 3, 6, 1, 2, 1, 2, 1, 0}, "integer", 24}
    }
)

local decoded_int = snmp.decode_message(response_with_int)
assert_eq(decoded_int.varbinds[1].type, "integer", "Integer type mismatch")
assert_eq(decoded_int.varbinds[1].value, 12345678, "Integer value mismatch")
print("  Integer value response decoded successfully")

-- 测试 7: 带 OID 值的响应
print("Test 7: Response with OID values")
local response_with_oid = snmp.encode_get_response(
    snmp.VERSION_2C,
    "public",
    88888,
    snmp.NO_ERROR,
    0,
    {
        {{1, 3, 6, 1, 2, 1, 1, 2, 0}, "oid", {1, 3, 6, 1, 4, 1, 8072, 3, 2, 10}}
    }
)

local decoded_oid = snmp.decode_message(response_with_oid)
assert_eq(decoded_oid.varbinds[1].type, "oid", "OID type mismatch")
assert_table_eq(decoded_oid.varbinds[1].value, {1, 3, 6, 1, 4, 1, 8072, 3, 2, 10}, "OID value mismatch")
print("  OID value response decoded successfully")

-- 测试 8: NULL 值响应（常见于 GET 请求）
print("Test 8: Response with NULL values")
local response_with_null = snmp.encode_get_response(
    snmp.VERSION_2C,
    "public",
    77777,
    snmp.NO_ERROR,
    0,
    {
        {{1, 3, 6, 1, 2, 1, 1, 1, 0}, "null", nil}
    }
)

local decoded_null = snmp.decode_message(response_with_null)
assert_eq(decoded_null.varbinds[1].type, "null", "NULL type mismatch")
assert_eq(decoded_null.varbinds[1].value, nil, "NULL value mismatch")
print("  NULL value response decoded successfully")

-- 测试 9: 错误响应
print("Test 9: Error response")
local error_response = snmp.encode_get_response(
    snmp.VERSION_2C,
    "public",
    55555,
    snmp.NO_SUCH_NAME,
    1,  -- Error at first varbind
    {
        {{1, 3, 6, 1, 2, 1, 99, 99, 99}, "null", nil}
    }
)

local decoded_error = snmp.decode_message(error_response)
assert_eq(decoded_error.error_status, snmp.NO_SUCH_NAME, "Error status mismatch")
assert_eq(decoded_error.error_index, 1, "Error index mismatch")
print("  Error response decoded successfully")

-- 测试 10: 多个 varbinds
print("Test 10: Multiple varbinds")
local many_varbinds = snmp.encode_get_response(
    snmp.VERSION_2C,
    "public",
    44444,
    snmp.NO_ERROR,
    0,
    {
        {{1, 3, 6, 1, 2, 1, 1, 1, 0}, "string", "System Description"},
        {{1, 3, 6, 1, 2, 1, 1, 2, 0}, "oid", {1, 3, 6, 1, 4, 1, 99}},
        {{1, 3, 6, 1, 2, 1, 1, 3, 0}, "integer", 123456},
        {{1, 3, 6, 1, 2, 1, 1, 4, 0}, "string", "admin@example.com"},
        {{1, 3, 6, 1, 2, 1, 1, 5, 0}, "string", "hostname"}
    }
)

local decoded_many = snmp.decode_message(many_varbinds)
assert_eq(#decoded_many.varbinds, 5, "VarBind count mismatch")
assert_eq(decoded_many.varbinds[1].type, "string", "VB1 type mismatch")
assert_eq(decoded_many.varbinds[2].type, "oid", "VB2 type mismatch")
assert_eq(decoded_many.varbinds[3].type, "integer", "VB3 type mismatch")
assert_eq(decoded_many.varbinds[4].type, "string", "VB4 type mismatch")
assert_eq(decoded_many.varbinds[5].type, "string", "VB5 type mismatch")
print("  Multiple varbinds decoded successfully")

print("\nAll SNMP tests passed!")
