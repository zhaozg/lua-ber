#!/usr/bin/env luajit

--- OID (Object Identifier) 处理库
-- 提供 OID 的解析、格式化、编码和解码功能
-- @module oid
-- @author lua-ber
-- @license MIT

local bit = require('bit')
local buffer = require('string.buffer')

local oid = {}

--- OID 对象元表
-- 提供 OID 对象的方法和操作
local OID_MT = {
    __index = {}
}

--- 创建新的 OID 对象
-- @param components table|string OID 组件数组或点分字符串
-- @return table OID 对象
-- @usage
-- local o1 = oid.new({1, 3, 6, 1, 2, 1, 1, 1, 0})
-- local o2 = oid.new("1.3.6.1.2.1.1.1.0")
function oid.new(components)
    local obj = {
        components = {}
    }
    
    if type(components) == "string" then
        -- 解析点分字符串
        obj.components = oid.parse(components)
    elseif type(components) == "table" then
        -- 复制组件数组
        for i, v in ipairs(components) do
            obj.components[i] = v
        end
    else
        error("OID components must be a table or string")
    end
    
    return setmetatable(obj, OID_MT)
end

--- 解析点分 OID 字符串为组件数组
-- @param oid_str string 点分格式的 OID 字符串，如 "1.3.6.1.2.1"
-- @return table OID 组件数组
-- @usage
-- local components = oid.parse("1.3.6.1.2.1.1.1.0")
-- -- components = {1, 3, 6, 1, 2, 1, 1, 1, 0}
function oid.parse(oid_str)
    if type(oid_str) ~= "string" then
        error("OID string must be a string")
    end
    
    local components = {}
    for num in oid_str:gmatch("(%d+)") do
        local n = tonumber(num)
        if not n or n < 0 then
            error("Invalid OID component: " .. tostring(num))
        end
        table.insert(components, n)
    end
    
    if #components < 2 then
        error("OID must have at least two components")
    end
    
    return components
end

--- 格式化 OID 组件数组为点分字符串
-- @param components table OID 组件数组
-- @return string 点分格式的 OID 字符串
-- @usage
-- local str = oid.format({1, 3, 6, 1, 2, 1, 1, 1, 0})
-- -- str = "1.3.6.1.2.1.1.1.0"
function oid.format(components)
    if type(components) ~= "table" or #components < 2 then
        error("OID components must be a table with at least 2 elements")
    end
    
    return table.concat(components, ".")
end

--- 编码 OID 为 BER 格式（仅内容部分，不含标签和长度）
-- 实现 ASN.1 OID 的 BER 编码算法
-- @param components table OID 组件数组
-- @return string BER 编码的 OID 内容（不含标签和长度）
-- @usage
-- local ber_content = oid.encode_content({1, 3, 6, 1, 4, 1})
function oid.encode_content(components)
    if type(components) ~= "table" or #components < 2 then
        error("OID must have at least two components")
    end
    
    -- 编码前两个组件：X * 40 + Y
    local first = components[1] * 40 + components[2]
    local oid_data = buffer.new()
    
    -- 编码第一个字节（可能需要 VLQ 编码）
    if first < 128 then
        oid_data:put(string.char(first))
    else
        -- 使用 VLQ 编码大于 127 的值
        local bytes = {}
        local v = first
        while v > 0 do
            table.insert(bytes, 1, bit.bor(bit.band(v, 0x7F), 0x80))
            v = bit.rshift(v, 7)
        end
        -- 最后一个字节的最高位应为 0
        bytes[#bytes] = bit.band(bytes[#bytes], 0x7F)
        for _, byte in ipairs(bytes) do
            oid_data:put(string.char(byte))
        end
    end
    
    -- 编码剩余组件
    for i = 3, #components do
        local comp = components[i]
        if comp < 0 then
            error("OID components cannot be negative")
        end
        
        if comp < 128 then
            -- 单字节编码
            oid_data:put(string.char(comp))
        else
            -- VLQ 编码
            local comp_bytes = {}
            local v = comp
            while v > 0 do
                table.insert(comp_bytes, 1, bit.bor(bit.band(v, 0x7F), 0x80))
                v = bit.rshift(v, 7)
            end
            -- 最后一个字节的最高位应为 0
            comp_bytes[#comp_bytes] = bit.band(comp_bytes[#comp_bytes], 0x7F)
            
            for _, byte in ipairs(comp_bytes) do
                oid_data:put(string.char(byte))
            end
        end
    end
    
    return tostring(oid_data)
end

--- 解码 BER 格式的 OID 内容（不含标签和长度）
-- @param data string BER 编码的 OID 内容
-- @return table OID 组件数组
-- @usage
-- local components = oid.decode_content(ber_data)
function oid.decode_content(data)
    if type(data) ~= "string" or #data == 0 then
        error("OID data must be a non-empty string")
    end
    
    local components = {}
    local pos = 1
    
    -- 解码第一个值（包含前两个组件，使用 VLQ 编码）
    local first_value = 0
    local byte
    
    repeat
        if pos > #data then
            error("Incomplete OID data")
        end
        byte = data:byte(pos)
        pos = pos + 1
        first_value = bit.bor(bit.lshift(first_value, 7), bit.band(byte, 0x7F))
    until bit.band(byte, 0x80) == 0
    
    -- 第一个值包含两个组件
    -- 根据 X.690 规范：
    -- - 如果 value < 40，则 X=0, Y=value
    -- - 如果 40 <= value < 80，则 X=1, Y=value-40
    -- - 如果 value >= 80，则 X=2, Y=value-80
    local first_component, second_component
    if first_value < 40 then
        first_component = 0
        second_component = first_value
    elseif first_value < 80 then
        first_component = 1
        second_component = first_value - 40
    else
        first_component = 2
        second_component = first_value - 80
    end
    
    table.insert(components, first_component)
    table.insert(components, second_component)
    
    -- 解码剩余组件
    while pos <= #data do
        local value = 0
        
        repeat
            if pos > #data then
                error("Incomplete OID component")
            end
            byte = data:byte(pos)
            pos = pos + 1
            value = bit.bor(bit.lshift(value, 7), bit.band(byte, 0x7F))
        until bit.band(byte, 0x80) == 0
        
        table.insert(components, value)
    end
    
    return components
end

--- 比较两个 OID 是否相等
-- @param oid1 table 第一个 OID 组件数组
-- @param oid2 table 第二个 OID 组件数组
-- @return boolean 如果相等返回 true
-- @usage
-- local eq = oid.equals({1, 3, 6, 1}, {1, 3, 6, 1})  -- true
function oid.equals(oid1, oid2)
    if #oid1 ~= #oid2 then
        return false
    end
    
    for i = 1, #oid1 do
        if oid1[i] ~= oid2[i] then
            return false
        end
    end
    
    return true
end

--- 检查 OID1 是否是 OID2 的前缀
-- @param oid1 table 可能的前缀 OID
-- @param oid2 table 被检查的 OID
-- @return boolean 如果 oid1 是 oid2 的前缀返回 true
-- @usage
-- local is_prefix = oid.is_prefix({1, 3, 6}, {1, 3, 6, 1, 2, 1})  -- true
function oid.is_prefix(oid1, oid2)
    if #oid1 > #oid2 then
        return false
    end
    
    for i = 1, #oid1 do
        if oid1[i] ~= oid2[i] then
            return false
        end
    end
    
    return true
end

--- 比较两个 OID 的大小
-- @param oid1 table 第一个 OID 组件数组
-- @param oid2 table 第二个 OID 组件数组
-- @return number 返回 -1（oid1 < oid2）、0（相等）或 1（oid1 > oid2）
-- @usage
-- local cmp = oid.compare({1, 3, 6}, {1, 3, 7})  -- -1
function oid.compare(oid1, oid2)
    local min_len = math.min(#oid1, #oid2)
    
    for i = 1, min_len do
        if oid1[i] < oid2[i] then
            return -1
        elseif oid1[i] > oid2[i] then
            return 1
        end
    end
    
    if #oid1 < #oid2 then
        return -1
    elseif #oid1 > #oid2 then
        return 1
    else
        return 0
    end
end

--- 验证 OID 是否有效
-- @param components table OID 组件数组
-- @return boolean 如果有效返回 true
-- @return string|nil 如果无效返回错误消息
-- @usage
-- local valid, err = oid.validate({1, 3, 6, 1, 2, 1})
function oid.validate(components)
    if type(components) ~= "table" then
        return false, "OID components must be a table"
    end
    
    if #components < 2 then
        return false, "OID must have at least two components"
    end
    
    -- 第一个组件必须是 0, 1 或 2
    if components[1] < 0 or components[1] > 2 then
        return false, "First OID component must be 0, 1, or 2"
    end
    
    -- 第二个组件的范围取决于第一个组件
    -- 当第一个为 0 或 1 时，第二个必须 < 40
    -- 当第一个为 2 时，第二个可以是任意值
    if components[1] < 2 and components[2] >= 40 then
        return false, "Second component must be < 40 when first component is 0 or 1"
    end
    
    -- 所有组件必须是非负整数
    for i, v in ipairs(components) do
        if type(v) ~= "number" or v < 0 or v ~= math.floor(v) then
            return false, "OID component " .. i .. " must be a non-negative integer"
        end
    end
    
    return true
end

--- OID 对象方法：转换为字符串
function OID_MT.__index:to_string()
    return oid.format(self.components)
end

--- OID 对象方法：获取组件数组
function OID_MT.__index:get_components()
    return self.components
end

--- OID 对象方法：获取父 OID
-- @return table|nil 父 OID 对象，如果没有父则返回 nil
function OID_MT.__index:parent()
    if #self.components <= 2 then
        return nil
    end
    
    local parent_components = {}
    for i = 1, #self.components - 1 do
        parent_components[i] = self.components[i]
    end
    
    return oid.new(parent_components)
end

--- OID 对象方法：添加子 OID
-- @param sub number|table 子组件或子组件数组
-- @return table 新的 OID 对象
function OID_MT.__index:append(sub)
    local new_components = {}
    for i, v in ipairs(self.components) do
        new_components[i] = v
    end
    
    if type(sub) == "number" then
        table.insert(new_components, sub)
    elseif type(sub) == "table" then
        for _, v in ipairs(sub) do
            table.insert(new_components, v)
        end
    else
        error("Sub-component must be a number or table")
    end
    
    return oid.new(new_components)
end

--- OID 对象元方法：相等比较
function OID_MT.__eq(a, b)
    return oid.equals(a.components, b.components)
end

--- OID 对象元方法：小于比较
function OID_MT.__lt(a, b)
    return oid.compare(a.components, b.components) < 0
end

--- OID 对象元方法：小于等于比较
function OID_MT.__le(a, b)
    return oid.compare(a.components, b.components) <= 0
end

--- OID 对象元方法：字符串表示
function OID_MT.__tostring(o)
    return o:to_string()
end

--- 常见的 OID 前缀常量
-- @field INTERNET 互联网 OID 前缀 (1.3.6.1)
-- @field PRIVATE 私有企业 OID 前缀 (1.3.6.1.4.1)
-- @field MGMT 管理 OID 前缀 (1.3.6.1.2)
-- @field EXPERIMENTAL 实验 OID 前缀 (1.3.6.1.3)
-- @field SNMPV2 SNMPv2 OID 前缀 (1.3.6.1.6)
oid.PREFIX = {
    INTERNET = {1, 3, 6, 1},
    PRIVATE = {1, 3, 6, 1, 4, 1},
    MGMT = {1, 3, 6, 1, 2},
    EXPERIMENTAL = {1, 3, 6, 1, 3},
    SNMPV2 = {1, 3, 6, 1, 6},
}

--- 常见的 SNMP MIB-2 OID
-- @field SYSTEM 系统组 (1.3.6.1.2.1.1)
-- @field INTERFACES 接口组 (1.3.6.1.2.1.2)
-- @field IP IP组 (1.3.6.1.2.1.4)
-- @field ICMP ICMP组 (1.3.6.1.2.1.5)
-- @field TCP TCP组 (1.3.6.1.2.1.6)
-- @field UDP UDP组 (1.3.6.1.2.1.7)
-- @field SNMP SNMP组 (1.3.6.1.2.1.11)
oid.MIB2 = {
    SYSTEM = {1, 3, 6, 1, 2, 1, 1},
    INTERFACES = {1, 3, 6, 1, 2, 1, 2},
    IP = {1, 3, 6, 1, 2, 1, 4},
    ICMP = {1, 3, 6, 1, 2, 1, 5},
    TCP = {1, 3, 6, 1, 2, 1, 6},
    UDP = {1, 3, 6, 1, 2, 1, 7},
    SNMP = {1, 3, 6, 1, 2, 1, 11},
}

return oid
