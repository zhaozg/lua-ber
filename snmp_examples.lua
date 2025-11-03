#!/usr/bin/env luajit

--- SNMP 使用示例
-- 演示如何使用 snmp.lua 库进行 SNMP 操作
-- @script snmp_examples

local snmp = require('snmp')

print("=== SNMP 使用示例 ===\n")

-- 示例 1: 创建 SNMP GetRequest
print("示例 1: 创建 SNMP GetRequest")
print("查询系统描述 (sysDescr) 和系统名称 (sysName)")

local get_request = snmp.encode_get_request(
    snmp.VERSION_2C,     -- SNMP 版本 v2c
    "public",            -- 团体字符串
    12345,               -- 请求 ID
    {
        {1, 3, 6, 1, 2, 1, 1, 1, 0},  -- sysDescr.0
        {1, 3, 6, 1, 2, 1, 1, 5, 0}   -- sysName.0
    }
)

print("GetRequest 消息已生成，长度: " .. #get_request .. " 字节")
-- 在实际应用中，你可以通过 UDP socket 将 get_request 发送到 SNMP 代理
-- 例如: sock:sendto(get_request, snmp_agent_ip, 161)
print()

-- 示例 2: 创建 SNMP GetNextRequest
print("示例 2: 创建 SNMP GetNextRequest")
print("遍历 system 组 (1.3.6.1.2.1.1)")

local get_next = snmp.encode_get_next_request(
    snmp.VERSION_2C,
    "public",
    12346,
    {
        {1, 3, 6, 1, 2, 1, 1}  -- system 组的基础 OID
    }
)

print("GetNextRequest 消息已生成，长度: " .. #get_next .. " 字节")
print()

-- 示例 3: 创建 SNMP SetRequest
print("示例 3: 创建 SNMP SetRequest")
print("设置系统名称和位置")

local set_request = snmp.encode_set_request(
    snmp.VERSION_2C,
    "private",           -- 写操作通常需要不同的团体字符串
    12347,
    {
        {{1, 3, 6, 1, 2, 1, 1, 5, 0}, "string", "server01.example.com"},
        {{1, 3, 6, 1, 2, 1, 1, 6, 0}, "string", "机房 A - 机架 42"}
    }
)

print("SetRequest 消息已生成，长度: " .. #set_request .. " 字节")
print()

-- 示例 4: 解析 SNMP 响应
print("示例 4: 解析 SNMP GetResponse")

-- 模拟一个响应（在实际应用中，这将从网络接收）
local response = snmp.encode_get_response(
    snmp.VERSION_2C,
    "public",
    12345,              -- 与请求相同的 ID
    snmp.NO_ERROR,      -- 无错误
    0,                  -- 错误索引
    {
        {{1, 3, 6, 1, 2, 1, 1, 1, 0}, "string", "Linux Ubuntu 22.04 LTS x86_64"},
        {{1, 3, 6, 1, 2, 1, 1, 5, 0}, "string", "webserver01"}
    }
)

-- 解析响应
local decoded = snmp.decode_message(response)

print("SNMP 版本: " .. (decoded.version == snmp.VERSION_2C and "v2c" or "v" .. decoded.version))
print("团体字符串: " .. decoded.community)
print("请求 ID: " .. decoded.request_id)
print("错误状态: " .. decoded.error_status .. " (" .. (decoded.error_status == 0 and "无错误" or "有错误") .. ")")
print("错误索引: " .. decoded.error_index)
print("变量绑定数量: " .. #decoded.varbinds)
print()

for i, vb in ipairs(decoded.varbinds) do
    print("  VarBind #" .. i .. ":")
    print("    OID: " .. snmp.format_oid(vb.oid))
    print("    类型: " .. vb.type)
    if vb.type == "string" then
        print("    值: " .. vb.value)
    elseif vb.type == "integer" then
        print("    值: " .. vb.value)
    elseif vb.type == "oid" then
        print("    值: " .. snmp.format_oid(vb.value))
    elseif vb.type == "null" then
        print("    值: NULL")
    else
        print("    值: " .. tostring(vb.value))
    end
end
print()

-- 示例 5: 常见的 SNMP OID
print("示例 5: 常见的系统 SNMP OID")
print()

local common_oids = {
    {"sysDescr",     "1.3.6.1.2.1.1.1.0",   "系统描述"},
    {"sysObjectID",  "1.3.6.1.2.1.1.2.0",   "系统对象标识符"},
    {"sysUpTime",    "1.3.6.1.2.1.1.3.0",   "系统运行时间"},
    {"sysContact",   "1.3.6.1.2.1.1.4.0",   "系统联系人"},
    {"sysName",      "1.3.6.1.2.1.1.5.0",   "系统名称"},
    {"sysLocation",  "1.3.6.1.2.1.1.6.0",   "系统位置"},
    {"sysServices",  "1.3.6.1.2.1.1.7.0",   "系统服务"},
}

for _, oid_info in ipairs(common_oids) do
    local name, oid_str, desc = oid_info[1], oid_info[2], oid_info[3]
    print(string.format("  %-15s %s", name, oid_str))
    print(string.format("  %s%s", string.rep(" ", 15), desc))
end
print()

-- 示例 6: OID 字符串操作
print("示例 6: OID 字符串格式化和解析")

local oid_array = {1, 3, 6, 1, 2, 1, 1, 1, 0}
local oid_string = snmp.format_oid(oid_array)
print("OID 数组: {" .. table.concat(oid_array, ", ") .. "}")
print("格式化为字符串: " .. oid_string)

local parsed = snmp.parse_oid("1.3.6.1.4.1.8072.3.2.10")
print("解析 '1.3.6.1.4.1.8072.3.2.10': {" .. table.concat(parsed, ", ") .. "}")
print()

-- 示例 7: 错误处理
print("示例 7: SNMP 错误响应处理")

local error_response = snmp.encode_get_response(
    snmp.VERSION_2C,
    "public",
    99999,
    snmp.NO_SUCH_NAME,  -- 错误：没有这样的对象
    2,                  -- 第2个变量绑定出错
    {
        {{1, 3, 6, 1, 2, 1, 1, 1, 0}, "string", "test"},
        {{1, 3, 6, 1, 99, 99, 99, 99}, "null", nil}  -- 不存在的 OID
    }
)

local decoded_error = snmp.decode_message(error_response)

local error_names = {
    [snmp.NO_ERROR] = "无错误",
    [snmp.TOO_BIG] = "响应太大",
    [snmp.NO_SUCH_NAME] = "没有这样的对象",
    [snmp.BAD_VALUE] = "错误的值",
    [snmp.READ_ONLY] = "只读",
    [snmp.GEN_ERR] = "通用错误"
}

print("错误状态: " .. decoded_error.error_status .. " (" .. (error_names[decoded_error.error_status] or "未知错误") .. ")")
print("错误索引: " .. decoded_error.error_index .. " (第 " .. decoded_error.error_index .. " 个变量绑定)")
print()

-- 示例 8: 完整的 SNMP 查询流程
print("示例 8: 模拟完整的 SNMP 查询流程")
print()

-- 步骤 1: 构建请求
print("1. 构建 GetRequest")
local req_oids = {
    {1, 3, 6, 1, 2, 1, 1, 3, 0},  -- sysUpTime
    {1, 3, 6, 1, 2, 1, 2, 1, 0}   -- ifNumber (网络接口数量)
}

local request = snmp.encode_get_request(snmp.VERSION_2C, "public", 54321, req_oids)
print("   请求已构建，包含 " .. #req_oids .. " 个 OID")

-- 步骤 2: 发送请求（伪代码）
print("2. 发送请求到 SNMP 代理")
print("   --> udp_socket:sendto(request, '192.168.1.1', 161)")

-- 步骤 3: 接收响应（伪代码）
print("3. 接收响应")
print("   <-- response_data = udp_socket:recv()")

-- 步骤 4: 解析响应
print("4. 解析响应")
-- 模拟响应
local simulated_response = snmp.encode_get_response(
    snmp.VERSION_2C,
    "public",
    54321,
    snmp.NO_ERROR,
    0,
    {
        {{1, 3, 6, 1, 2, 1, 1, 3, 0}, "integer", 3654321},  -- uptime in centiseconds
        {{1, 3, 6, 1, 2, 1, 2, 1, 0}, "integer", 4}         -- 4 interfaces
    }
)

local result = snmp.decode_message(simulated_response)

-- 步骤 5: 处理结果
print("5. 处理结果")
for i, vb in ipairs(result.varbinds) do
    local oid_str = snmp.format_oid(vb.oid)
    if oid_str == "1.3.6.1.2.1.1.3.0" then
        local days = math.floor(vb.value / 8640000)
        local hours = math.floor((vb.value % 8640000) / 360000)
        local minutes = math.floor((vb.value % 360000) / 6000)
        print("   系统运行时间: " .. days .. " 天 " .. hours .. " 小时 " .. minutes .. " 分钟")
    elseif oid_str == "1.3.6.1.2.1.2.1.0" then
        print("   网络接口数量: " .. vb.value)
    end
end
print()

print("=== 示例结束 ===")
