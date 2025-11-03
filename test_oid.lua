#!/usr/bin/env luajit

--- OID 库测试
-- 测试 oid.lua 模块的所有功能

local oid = require('oid')

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

print("Testing OID library...")

-- 测试 1: 解析点分字符串
print("Test 1: Parse OID string")
local components = oid.parse("1.3.6.1.2.1.1.1.0")
assert_table_eq(components, {1, 3, 6, 1, 2, 1, 1, 1, 0}, "Parse OID string failed")
print("  ✓ Parse OID string passed")

-- 测试 2: 格式化 OID 为字符串
print("Test 2: Format OID to string")
local str = oid.format({1, 3, 6, 1, 2, 1, 1, 1, 0})
assert_eq(str, "1.3.6.1.2.1.1.1.0", "Format OID failed")
print("  ✓ Format OID passed")

-- 测试 3: 编码 OID 内容
print("Test 3: Encode OID content")
local encoded = oid.encode_content({1, 3, 6, 1, 4, 1})
assert(#encoded > 0, "Encode OID content failed")
print("  ✓ Encode OID content passed (" .. #encoded .. " bytes)")

-- 测试 4: 解码 OID 内容
print("Test 4: Decode OID content")
local decoded = oid.decode_content(encoded)
assert_table_eq(decoded, {1, 3, 6, 1, 4, 1}, "Decode OID content failed")
print("  ✓ Decode OID content passed")

-- 测试 5: 编码/解码往返测试
print("Test 5: Encode/decode round-trip")
local test_oids = {
    {1, 3, 6, 1, 2, 1, 1, 1, 0},
    {2, 5, 4, 3},
    {1, 2, 840, 113549, 1, 1, 5},
    {1, 3, 6, 1, 4, 1, 8072, 3, 2, 10},
    {2, 16, 840, 1, 101, 3, 4, 2, 1},  -- SHA-256
}

for i, test_oid in ipairs(test_oids) do
    local enc = oid.encode_content(test_oid)
    local dec = oid.decode_content(enc)
    assert_table_eq(dec, test_oid, "Round-trip failed for OID " .. i)
end
print("  ✓ Round-trip tests passed for " .. #test_oids .. " OIDs")

-- 测试 6: OID 比较
print("Test 6: OID comparison")
assert(oid.equals({1, 3, 6, 1}, {1, 3, 6, 1}), "Equals comparison failed")
assert(not oid.equals({1, 3, 6, 1}, {1, 3, 6, 2}), "Not equals comparison failed")
assert_eq(oid.compare({1, 3, 6}, {1, 3, 7}), -1, "Less than comparison failed")
assert_eq(oid.compare({1, 3, 7}, {1, 3, 6}), 1, "Greater than comparison failed")
assert_eq(oid.compare({1, 3, 6}, {1, 3, 6}), 0, "Equal comparison failed")
print("  ✓ Comparison tests passed")

-- 测试 7: 前缀检查
print("Test 7: Prefix check")
assert(oid.is_prefix({1, 3, 6}, {1, 3, 6, 1, 2, 1}), "Prefix check failed")
assert(not oid.is_prefix({1, 3, 7}, {1, 3, 6, 1, 2, 1}), "Non-prefix check failed")
assert(oid.is_prefix({1, 3, 6, 1}, {1, 3, 6, 1}), "Self-prefix check failed")
print("  ✓ Prefix tests passed")

-- 测试 8: OID 验证
print("Test 8: OID validation")
local valid, err = oid.validate({1, 3, 6, 1, 2, 1})
assert(valid, "Valid OID rejected: " .. tostring(err))

valid, err = oid.validate({1})
assert(not valid, "Invalid OID accepted (too short)")

valid, err = oid.validate({3, 0})
assert(not valid, "Invalid OID accepted (first component > 2)")

valid, err = oid.validate({1, 50})
assert(not valid, "Invalid OID accepted (second component >= 40 when first < 2)")

valid, err = oid.validate({1, 3, -1})
assert(not valid, "Invalid OID accepted (negative component)")

print("  ✓ Validation tests passed")

-- 测试 9: OID 对象创建
print("Test 9: OID object creation")
local oid1 = oid.new({1, 3, 6, 1, 2, 1, 1, 1, 0})
assert_eq(oid1:to_string(), "1.3.6.1.2.1.1.1.0", "OID object to_string failed")

local oid2 = oid.new("1.3.6.1.2.1.1.5.0")
assert_table_eq(oid2:get_components(), {1, 3, 6, 1, 2, 1, 1, 5, 0}, "OID object from string failed")
print("  ✓ OID object creation passed")

-- 测试 10: OID 对象方法
print("Test 10: OID object methods")
local base_oid = oid.new({1, 3, 6, 1})
local extended_oid = base_oid:append(2):append(1)
assert_eq(extended_oid:to_string(), "1.3.6.1.2.1", "OID append failed")

local parent = extended_oid:parent()
assert_eq(parent:to_string(), "1.3.6.1.2", "OID parent failed")

-- 测试多个组件追加
local multi_append = base_oid:append({4, 1, 99})
assert_eq(multi_append:to_string(), "1.3.6.1.4.1.99", "OID multi-append failed")
print("  ✓ OID object methods passed")

-- 测试 11: OID 对象比较运算符
print("Test 11: OID object operators")
local oid_a = oid.new({1, 3, 6, 1})
local oid_b = oid.new({1, 3, 6, 1})
local oid_c = oid.new({1, 3, 6, 2})

assert(oid_a == oid_b, "OID equality operator failed")
assert(oid_a ~= oid_c, "OID inequality operator failed")
assert(oid_a < oid_c, "OID less than operator failed")
assert(oid_a <= oid_b, "OID less than or equal operator failed")

-- 测试 tostring 元方法
assert_eq(tostring(oid_a), "1.3.6.1", "OID tostring failed")
print("  ✓ OID operators passed")

-- 测试 12: 常量定义
print("Test 12: OID constants")
assert_table_eq(oid.PREFIX.INTERNET, {1, 3, 6, 1}, "INTERNET prefix wrong")
assert_table_eq(oid.PREFIX.PRIVATE, {1, 3, 6, 1, 4, 1}, "PRIVATE prefix wrong")
assert_table_eq(oid.MIB2.SYSTEM, {1, 3, 6, 1, 2, 1, 1}, "MIB2 SYSTEM wrong")
assert_table_eq(oid.MIB2.INTERFACES, {1, 3, 6, 1, 2, 1, 2}, "MIB2 INTERFACES wrong")
print("  ✓ Constants passed")

-- 测试 13: 特殊 OID 编码（大数值）
print("Test 13: Large component encoding")
local large_oid = {1, 2, 840, 113549, 1, 1, 11}  -- PKCS#1 SHA-512 with RSA
local enc_large = oid.encode_content(large_oid)
local dec_large = oid.decode_content(enc_large)
assert_table_eq(dec_large, large_oid, "Large component OID failed")
print("  ✓ Large component encoding passed")

-- 测试 14: 边界情况
print("Test 14: Edge cases")
-- 最小有效 OID
local min_oid = {0, 0}
local enc_min = oid.encode_content(min_oid)
local dec_min = oid.decode_content(enc_min)
assert_table_eq(dec_min, min_oid, "Minimum OID failed")

-- 第一个组件为 2 的 OID
local oid_2 = {2, 999, 1}
local enc_2 = oid.encode_content(oid_2)
local dec_2 = oid.decode_content(enc_2)
assert_table_eq(dec_2, oid_2, "OID with first component = 2 failed")

print("  ✓ Edge cases passed")

-- 测试 15: 错误处理
print("Test 15: Error handling")
local function expect_error(fn, msg)
    local ok, err = pcall(fn)
    assert(not ok, "Expected error but function succeeded: " .. (msg or ""))
end

expect_error(function() oid.parse("invalid") end, "Parse invalid OID")
expect_error(function() oid.parse("1") end, "Parse too short OID")
expect_error(function() oid.encode_content({1}) end, "Encode too short OID")
expect_error(function() oid.encode_content({1, 3, -1}) end, "Encode negative component")
expect_error(function() oid.format({}) end, "Format empty OID")
expect_error(function() oid.decode_content("") end, "Decode empty data")

print("  ✓ Error handling passed")

-- 测试 16: 常见 SNMP OID
print("Test 16: Common SNMP OIDs")
local snmp_oids = {
    {name = "sysDescr", oid = {1, 3, 6, 1, 2, 1, 1, 1, 0}},
    {name = "sysObjectID", oid = {1, 3, 6, 1, 2, 1, 1, 2, 0}},
    {name = "sysUpTime", oid = {1, 3, 6, 1, 2, 1, 1, 3, 0}},
    {name = "sysContact", oid = {1, 3, 6, 1, 2, 1, 1, 4, 0}},
    {name = "sysName", oid = {1, 3, 6, 1, 2, 1, 1, 5, 0}},
    {name = "sysLocation", oid = {1, 3, 6, 1, 2, 1, 1, 6, 0}},
}

for _, item in ipairs(snmp_oids) do
    local enc = oid.encode_content(item.oid)
    local dec = oid.decode_content(enc)
    assert_table_eq(dec, item.oid, item.name .. " OID failed")
end
print("  ✓ SNMP OIDs passed (" .. #snmp_oids .. " OIDs)")

print("\n✅ All OID library tests passed!")
