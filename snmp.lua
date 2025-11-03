#!/usr/bin/env luajit

--- SNMP (Simple Network Management Protocol) 编码/解码库
-- 基于 BER 编码实现 SNMP v1/v2c/v3 消息的编码和解码
-- @module snmp
-- @author lua-ber
-- @license MIT

local ber = require('ber')

local snmp = {}

--- SNMP 版本常量
-- @field VERSION_1 SNMP v1 (0)
-- @field VERSION_2C SNMP v2c (1)
-- @field VERSION_3 SNMP v3 (3)
snmp.VERSION_1 = 0
snmp.VERSION_2C = 1
snmp.VERSION_3 = 3

--- SNMP PDU 类型常量
-- @field GET_REQUEST GetRequest PDU (0xA0)
-- @field GET_NEXT_REQUEST GetNextRequest PDU (0xA1)
-- @field GET_RESPONSE GetResponse PDU (0xA2)
-- @field SET_REQUEST SetRequest PDU (0xA3)
-- @field TRAP Trap PDU (0xA4, SNMPv1 only)
-- @field GET_BULK_REQUEST GetBulkRequest PDU (0xA5, SNMPv2c/v3)
-- @field INFORM_REQUEST InformRequest PDU (0xA6, SNMPv2c/v3)
-- @field TRAP_V2 SNMPv2-Trap PDU (0xA7, SNMPv2c/v3)
-- @field REPORT Report PDU (0xA8, SNMPv3)
snmp.GET_REQUEST = 0xA0
snmp.GET_NEXT_REQUEST = 0xA1
snmp.GET_RESPONSE = 0xA2
snmp.SET_REQUEST = 0xA3
snmp.TRAP = 0xA4
snmp.GET_BULK_REQUEST = 0xA5
snmp.INFORM_REQUEST = 0xA6
snmp.TRAP_V2 = 0xA7
snmp.REPORT = 0xA8

--- SNMP 应用类型常量
-- 这些是 SNMP 特定的 BER 标签
-- @field IP_ADDRESS IpAddress (0x40)
-- @field COUNTER32 Counter32 (0x41)
-- @field GAUGE32 Gauge32 (0x42)
-- @field TIME_TICKS TimeTicks (0x43)
-- @field OPAQUE Opaque (0x44)
-- @field COUNTER64 Counter64 (0x46)
snmp.IP_ADDRESS = 0x40
snmp.COUNTER32 = 0x41
snmp.GAUGE32 = 0x42
snmp.TIME_TICKS = 0x43
snmp.OPAQUE = 0x44
snmp.COUNTER64 = 0x46

--- SNMP 错误状态常量
-- @field NO_ERROR 无错误 (0)
-- @field TOO_BIG 响应太大 (1)
-- @field NO_SUCH_NAME 没有这样的变量 (2)
-- @field BAD_VALUE 错误的值 (3)
-- @field READ_ONLY 只读 (4)
-- @field GEN_ERR 通用错误 (5)
snmp.NO_ERROR = 0
snmp.TOO_BIG = 1
snmp.NO_SUCH_NAME = 2
snmp.BAD_VALUE = 3
snmp.READ_ONLY = 4
snmp.GEN_ERR = 5

--- 编码 SNMP GetRequest PDU
-- 创建一个 SNMP GetRequest 消息，用于查询 SNMP 代理的变量值
-- @param version number SNMP 版本 (使用 snmp.VERSION_* 常量)
-- @param community string 团体字符串 (SNMPv1/v2c)
-- @param request_id number 请求 ID
-- @param oids table OID 数组，每个 OID 是一个数字数组
-- @return string BER 编码的 SNMP GetRequest 消息
-- @usage
-- local msg = snmp.encode_get_request(snmp.VERSION_2C, "public", 1, {
--     {1, 3, 6, 1, 2, 1, 1, 1, 0},  -- sysDescr
--     {1, 3, 6, 1, 2, 1, 1, 5, 0}   -- sysName
-- })
function snmp.encode_get_request(version, community, request_id, oids)
    local enc = ber.new_encoder()
    
    -- SNMP Message ::= SEQUENCE
    local msg_seq = enc:start_sequence()
    
    -- Version
    msg_seq:encode_integer(version)
    
    -- Community
    msg_seq:encode_octet_string(community)
    
    -- PDU ::= GetRequest-PDU
    local pdu_seq = ber.new_encoder()
    
    -- Request ID
    pdu_seq:encode_integer(request_id)
    
    -- Error Status (0 = noError)
    pdu_seq:encode_integer(snmp.NO_ERROR)
    
    -- Error Index (0)
    pdu_seq:encode_integer(0)
    
    -- Variable Bindings
    local varbind_seq = pdu_seq:start_sequence()
    for _, oid in ipairs(oids) do
        local vb_seq = varbind_seq:start_sequence()
        vb_seq:encode_oid(oid)
        vb_seq:encode_null()  -- Value = NULL for GET requests
        varbind_seq:end_sequence(vb_seq)
    end
    pdu_seq:end_sequence(varbind_seq)
    
    -- 完成 PDU 编码并封装为 GetRequest 标签
    local pdu_content = pdu_seq:get()
    msg_seq:encode_with_tag(ber.CLASS_CONTEXT, ber.CONSTRUCTED, 0, pdu_content)  -- GetRequest tag
    
    enc:end_sequence(msg_seq)
    
    return enc:get()
end

--- 编码 SNMP GetNextRequest PDU
-- 创建一个 SNMP GetNextRequest 消息，用于遍历 MIB 树
-- @param version number SNMP 版本
-- @param community string 团体字符串
-- @param request_id number 请求 ID
-- @param oids table OID 数组
-- @return string BER 编码的 SNMP GetNextRequest 消息
-- @usage
-- local msg = snmp.encode_get_next_request(snmp.VERSION_2C, "public", 2, {
--     {1, 3, 6, 1, 2, 1, 1}
-- })
function snmp.encode_get_next_request(version, community, request_id, oids)
    local enc = ber.new_encoder()
    
    local msg_seq = enc:start_sequence()
    msg_seq:encode_integer(version)
    msg_seq:encode_octet_string(community)
    
    local pdu_seq = ber.new_encoder()
    pdu_seq:encode_integer(request_id)
    pdu_seq:encode_integer(snmp.NO_ERROR)
    pdu_seq:encode_integer(0)
    
    local varbind_seq = pdu_seq:start_sequence()
    for _, oid in ipairs(oids) do
        local vb_seq = varbind_seq:start_sequence()
        vb_seq:encode_oid(oid)
        vb_seq:encode_null()
        varbind_seq:end_sequence(vb_seq)
    end
    pdu_seq:end_sequence(varbind_seq)
    
    local pdu_content = pdu_seq:get()
    msg_seq:encode_with_tag(ber.CLASS_CONTEXT, ber.CONSTRUCTED, 1, pdu_content)  -- GetNextRequest tag
    enc:end_sequence(msg_seq)
    
    return enc:get()
end

--- 编码 SNMP SetRequest PDU
-- 创建一个 SNMP SetRequest 消息，用于设置 SNMP 代理的变量值
-- @param version number SNMP 版本
-- @param community string 团体字符串
-- @param request_id number 请求 ID
-- @param varbinds table 变量绑定数组，每个元素为 {oid, type, value}
-- @return string BER 编码的 SNMP SetRequest 消息
-- @usage
-- local msg = snmp.encode_set_request(snmp.VERSION_2C, "private", 3, {
--     {{1, 3, 6, 1, 2, 1, 1, 5, 0}, "string", "NewHostName"},
--     {{1, 3, 6, 1, 2, 1, 1, 6, 0}, "string", "Location"}
-- })
function snmp.encode_set_request(version, community, request_id, varbinds)
    local enc = ber.new_encoder()
    
    local msg_seq = enc:start_sequence()
    msg_seq:encode_integer(version)
    msg_seq:encode_octet_string(community)
    
    local pdu_seq = ber.new_encoder()
    pdu_seq:encode_integer(request_id)
    pdu_seq:encode_integer(snmp.NO_ERROR)
    pdu_seq:encode_integer(0)
    
    local varbind_seq = pdu_seq:start_sequence()
    for _, vb in ipairs(varbinds) do
        local oid, value_type, value = vb[1], vb[2], vb[3]
        local vb_seq = varbind_seq:start_sequence()
        vb_seq:encode_oid(oid)
        
        -- 根据类型编码值
        if value_type == "integer" then
            vb_seq:encode_integer(value)
        elseif value_type == "string" then
            vb_seq:encode_octet_string(value)
        elseif value_type == "oid" then
            vb_seq:encode_oid(value)
        elseif value_type == "counter32" then
            -- Counter32 是应用类型 [APPLICATION 1]
            local bytes = {}
            local v = value
            for i = 1, 4 do
                table.insert(bytes, 1, string.char(v % 256))
                v = math.floor(v / 256)
            end
            local counter_data = table.concat(bytes)
            vb_seq:encode_with_tag(ber.CLASS_APPLICATION, ber.PRIMITIVE, 1, counter_data)
        elseif value_type == "timeticks" then
            -- TimeTicks 是应用类型 [APPLICATION 3]
            local bytes = {}
            local v = value
            for i = 1, 4 do
                table.insert(bytes, 1, string.char(v % 256))
                v = math.floor(v / 256)
            end
            local ticks_data = table.concat(bytes)
            vb_seq:encode_with_tag(ber.CLASS_APPLICATION, ber.PRIMITIVE, 3, ticks_data)
        else
            error("encode_set_request: Unsupported value type '" .. tostring(value_type) .. "'. Supported types: integer, string, oid, counter32, timeticks")
        end
        
        varbind_seq:end_sequence(vb_seq)
    end
    pdu_seq:end_sequence(varbind_seq)
    
    local pdu_content = pdu_seq:get()
    msg_seq:encode_with_tag(ber.CLASS_CONTEXT, ber.CONSTRUCTED, 3, pdu_content)  -- SetRequest tag
    enc:end_sequence(msg_seq)
    
    return enc:get()
end

--- 解码 SNMP 消息
-- 解析 BER 编码的 SNMP 消息，返回消息内容
-- @param data string BER 编码的 SNMP 消息
-- @return table 包含 version, community, pdu_type, request_id, error_status, error_index, varbinds 的表
-- @usage
-- local msg = snmp.decode_message(response_data)
-- print("Version:", msg.version)
-- print("Community:", msg.community)
-- for i, vb in ipairs(msg.varbinds) do
--     print("OID:", table.concat(vb.oid, "."), "Value:", vb.value)
-- end
function snmp.decode_message(data)
    local dec = ber.new_decoder(data)
    
    -- SNMP Message SEQUENCE
    local msg_end = dec:start_sequence()
    
    -- Version
    local version = dec:decode_integer()
    
    -- Community
    local community = dec:decode_octet_string()
    
    -- PDU
    local pdu_tag = dec:decode_tag()
    local pdu_type = pdu_tag.tag
    local pdu_len = dec:decode_length()
    
    -- Request ID
    local request_id = dec:decode_integer()
    
    -- Error Status
    local error_status = dec:decode_integer()
    
    -- Error Index
    local error_index = dec:decode_integer()
    
    -- Variable Bindings
    local varbinds = {}
    local varbind_end = dec:start_sequence()
    
    while not dec:at_sequence_end(varbind_end) do
        local vb_end = dec:start_sequence()
        local oid = dec:decode_oid()
        
        -- 读取值（可能是多种类型）
        local pos = dec:get_position()
        local value_tag = dec:decode_tag()
        dec:set_position(pos)
        
        local value
        local value_type
        
        if value_tag.tag == ber.INTEGER then
            value = dec:decode_integer()
            value_type = "integer"
        elseif value_tag.tag == ber.OCTET_STRING then
            value = dec:decode_octet_string()
            value_type = "string"
        elseif value_tag.tag == ber.NULL then
            dec:decode_null()
            value = nil
            value_type = "null"
        elseif value_tag.tag == ber.OBJECT_IDENTIFIER then
            value = dec:decode_oid()
            value_type = "oid"
        elseif value_tag.tag == 1 and value_tag.class == ber.CLASS_APPLICATION then
            -- Counter32
            dec:decode_tag()
            local len = dec:decode_length()
            local bytes = dec:_read_bytes(len)
            value = 0
            for i = 1, #bytes do
                value = value * 256 + bytes:byte(i)
            end
            value_type = "counter32"
        elseif value_tag.tag == 2 and value_tag.class == ber.CLASS_APPLICATION then
            -- Gauge32
            dec:decode_tag()
            local len = dec:decode_length()
            local bytes = dec:_read_bytes(len)
            value = 0
            for i = 1, #bytes do
                value = value * 256 + bytes:byte(i)
            end
            value_type = "gauge32"
        elseif value_tag.tag == 3 and value_tag.class == ber.CLASS_APPLICATION then
            -- TimeTicks
            dec:decode_tag()
            local len = dec:decode_length()
            local bytes = dec:_read_bytes(len)
            value = 0
            for i = 1, #bytes do
                value = value * 256 + bytes:byte(i)
            end
            value_type = "timeticks"
        elseif value_tag.tag == 0 and value_tag.class == ber.CLASS_APPLICATION then
            -- IpAddress
            dec:decode_tag()
            local len = dec:decode_length()
            local bytes = dec:_read_bytes(len)
            value = {}
            for i = 1, #bytes do
                table.insert(value, bytes:byte(i))
            end
            value_type = "ipaddress"
        else
            -- 未知类型，跳过
            dec:decode_tag()
            local len = dec:decode_length()
            if len > 0 then
                dec:_read_bytes(len)
            end
            value = nil
            value_type = "unknown"
        end
        
        table.insert(varbinds, {
            oid = oid,
            value = value,
            type = value_type
        })
        
        assert(dec:at_sequence_end(vb_end), "VarBind sequence not at end")
    end
    
    return {
        version = version,
        community = community,
        pdu_type = pdu_type,
        request_id = request_id,
        error_status = error_status,
        error_index = error_index,
        varbinds = varbinds
    }
end

--- 编码 SNMP GetResponse PDU
-- 创建一个 SNMP GetResponse 消息，用于响应 GET/SET 请求
-- @param version number SNMP 版本
-- @param community string 团体字符串
-- @param request_id number 请求 ID (应与请求相同)
-- @param error_status number 错误状态 (使用 snmp.NO_ERROR 等常量)
-- @param error_index number 错误索引
-- @param varbinds table 变量绑定数组
-- @return string BER 编码的 SNMP GetResponse 消息
function snmp.encode_get_response(version, community, request_id, error_status, error_index, varbinds)
    local enc = ber.new_encoder()
    
    local msg_seq = enc:start_sequence()
    msg_seq:encode_integer(version)
    msg_seq:encode_octet_string(community)
    
    local pdu_seq = ber.new_encoder()
    pdu_seq:encode_integer(request_id)
    pdu_seq:encode_integer(error_status)
    pdu_seq:encode_integer(error_index)
    
    local varbind_seq = pdu_seq:start_sequence()
    for _, vb in ipairs(varbinds) do
        local oid, value_type, value = vb[1], vb[2], vb[3]
        local vb_seq = varbind_seq:start_sequence()
        vb_seq:encode_oid(oid)
        
        if value_type == "integer" then
            vb_seq:encode_integer(value)
        elseif value_type == "string" then
            vb_seq:encode_octet_string(value)
        elseif value_type == "oid" then
            vb_seq:encode_oid(value)
        elseif value_type == "null" then
            vb_seq:encode_null()
        else
            error("encode_get_response: Unsupported value type '" .. tostring(value_type) .. "'. Supported types: integer, string, oid, null")
        end
        
        varbind_seq:end_sequence(vb_seq)
    end
    pdu_seq:end_sequence(varbind_seq)
    
    local pdu_content = pdu_seq:get()
    msg_seq:encode_with_tag(ber.CLASS_CONTEXT, ber.CONSTRUCTED, 2, pdu_content)  -- GetResponse tag
    enc:end_sequence(msg_seq)
    
    return enc:get()
end

--- 格式化 OID 为点分字符串
-- @param oid table OID 数组
-- @return string 点分格式的 OID 字符串
function snmp.format_oid(oid)
    return table.concat(oid, ".")
end

--- 解析点分 OID 字符串为数组
-- @param oid_str string 点分格式的 OID 字符串
-- @return table OID 数组
function snmp.parse_oid(oid_str)
    local oid = {}
    for num in oid_str:gmatch("(%d+)") do
        table.insert(oid, tonumber(num))
    end
    return oid
end

return snmp
