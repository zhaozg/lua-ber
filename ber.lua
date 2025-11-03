#!/usr/bin/env luajit

local bit = require('bit')
local buffer = require('string.buffer')

--- BER (Basic Encoding Rules) 编码/解码库
-- 实现 ASN.1 BER 编码规则，支持高性能的二进制数据编码和解码
-- @module ber
local ber = {}

--- BER 类型标签常量
-- @field INTEGER 整数类型 (0x02)
-- @field OCTET_STRING 八位字节串类型 (0x04)
-- @field NULL 空类型 (0x05)
-- @field OBJECT_IDENTIFIER 对象标识符类型 (0x06)
-- @field SEQUENCE 序列类型 (0x30)
-- @field BOOLEAN 布尔类型 (0x01)
-- @field BIT_STRING 位串类型 (0x03)
-- @field UTF8_STRING UTF8字符串类型 (0x0C)
-- @field PRINTABLE_STRING 可打印字符串类型 (0x13)
-- @field IA5_STRING IA5字符串类型 (0x16)
-- @field UTC_TIME UTC时间类型 (0x17)
-- @field GENERALIZED_TIME 通用时间类型 (0x18)
ber.INTEGER = 0x02
ber.OCTET_STRING = 0x04
ber.NULL = 0x05
ber.OBJECT_IDENTIFIER = 0x06
ber.SEQUENCE = 0x30
ber.BOOLEAN = 0x01
ber.BIT_STRING = 0x03
ber.UTF8_STRING = 0x0C
ber.PRINTABLE_STRING = 0x13
ber.IA5_STRING = 0x16
ber.UTC_TIME = 0x17
ber.GENERALIZED_TIME = 0x18

--- BER 类标记常量
-- @field CLASS_UNIVERSAL 通用类 (0x00)
-- @field CLASS_APPLICATION 应用类 (0x40)
-- @field CLASS_CONTEXT 上下文特定类 (0x80)
-- @field CLASS_PRIVATE 私有类 (0xC0)
ber.CLASS_UNIVERSAL = 0x00
ber.CLASS_APPLICATION = 0x40
ber.CLASS_CONTEXT = 0x80
ber.CLASS_PRIVATE = 0xC0

--- BER 构造标记常量
-- @field PRIMITIVE 原始类型 (0x00)
-- @field CONSTRUCTED 构造类型 (0x20)
ber.PRIMITIVE = 0x00
ber.CONSTRUCTED = 0x20

--- 创建新的 BER 编码器
-- 返回一个编码器实例，用于增量构建 BER 编码数据
-- @return table 编码器实例，包含编码方法和缓冲区
-- @usage
-- local enc = ber.new_encoder()
-- enc:encode_integer(42)
-- enc:encode_octet_string("hello")
-- local data = enc:get()
function ber.new_encoder()
    local enc = {
        buf = buffer.new()
    }

    --- 内部方法：编码 VLQ (Variable Length Quantity)
    -- 实现变长数量编码算法，用于编码大整数和长标签
    -- @param v number 要编码的整数值
    -- @private
    function enc:_encode_vlq(v)
        if v < 128 then
            self.buf:put(string.char(v))
            return
        end

        local parts = {}
        while v > 0 do
            local part = bit.band(v, 0x7F)
            v = bit.rshift(v, 7)
            if #parts > 0 then
                part = bit.bor(part, 0x80)
            end
            table.insert(parts, 1, part)
        end

        for _, part in ipairs(parts) do
            self.buf:put(string.char(part))
        end
    end

    --- 内部方法：编码长度字段
    -- 根据 BER 长度编码规则处理短格式和长格式
    -- @param len number 要编码的长度值
    -- @private
    function enc:_encode_length(len)
        if len < 128 then
            self.buf:put(string.char(len))
        else
            local len_bytes = {}
            local tmp = len
            while tmp > 0 do
                table.insert(len_bytes, 1, bit.band(tmp, 0xFF))
                tmp = bit.rshift(tmp, 8)
            end
            self.buf:put(string.char(bit.bor(0x80, #len_bytes)))
            for _, byte in ipairs(len_bytes) do
                self.buf:put(string.char(byte))
            end
        end
    end

    --- 编码 BER 标签
    -- 根据 BER 标签编码规则处理短标签和长标签
    -- @param class number 标签类 (使用 ber.CLASS_* 常量)
    -- @param constructed number 构造标记 (ber.PRIMITIVE 或 ber.CONSTRUCTED)
    -- @param tag_number number 标签编号
    -- @usage
    -- enc:encode_tag(ber.CLASS_UNIVERSAL, ber.PRIMITIVE, ber.INTEGER)
    function enc:encode_tag(class, constructed, tag_number)
        if tag_number < 31 then
            -- 短标签格式：在一个字节内编码
            local tag_byte = bit.bor(class, constructed, tag_number)
        self.buf:put(string.char(tag_byte))
        else
            -- 长标签格式：第一个字节后跟 VLQ 编码的标签号
            local tag_byte = bit.bor(class, constructed, 0x1F)
            self.buf:put(tag_byte)
            self:_encode_vlq(tag_number)
        end
    end

    --- 编码整数类型
    -- 实现 BER 整数编码，支持正负整数和补码表示
    -- @param value number 要编码的整数值
    -- @usage
    -- enc:encode_integer(42)
    -- enc:encode_integer(-100)
    function enc:encode_integer(value)
        self:encode_tag(ber.CLASS_UNIVERSAL, ber.PRIMITIVE, ber.INTEGER)

        if value == 0 then
            -- 特殊处理零值
            self.buf:put(string.char(1)):put(string.char(0))
            return
        end

        local bytes = {}
        local negative = value < 0

        if negative then
            value = -value
        end

        -- 转换为二进制表示
        while value > 0 do
            table.insert(bytes, 1, bit.band(value, 0xFF))
            value = bit.rshift(value, 8)
        end

        -- 处理负数 (补码)
        if negative then
            -- 取反
            for i = 1, #bytes do
                bytes[i] = bit.bnot(bytes[i]) % 256
            end

            -- 加1
            local carry = 1
            for i = #bytes, 1, -1 do
                local sum = bytes[i] + carry
                bytes[i] = bit.band(sum, 0xFF)
                carry = bit.rshift(sum, 8)
            end

            -- 确保最高位为1（表示负数）
            if bit.band(bytes[1], 0x80) == 0 then
                table.insert(bytes, 1, 0xFF)
            end
        else
            -- 确保最高位为0（表示正数）
            if bit.band(bytes[1], 0x80) ~= 0 then
                table.insert(bytes, 1, 0)
            end
        end

        self:_encode_length(#bytes)
        for _, byte in ipairs(bytes) do
            self.buf:put(string.char(byte))
        end
    end

    --- 编码八位字节串类型
    -- @param data string 要编码的二进制数据
    -- @usage
    -- enc:encode_octet_string("hello")
    -- enc:encode_octet_string("\x01\x02\x03")
    function enc:encode_octet_string(data)
        self:encode_tag(ber.CLASS_UNIVERSAL, ber.PRIMITIVE, ber.OCTET_STRING)
        self:_encode_length(#data)
        self.buf:put(data)
    end

    --- 编码 NULL 类型
    -- NULL 类型没有内容，长度为0
    -- @usage
    -- enc:encode_null()
    function enc:encode_null()
        self:encode_tag(ber.CLASS_UNIVERSAL, ber.PRIMITIVE, ber.NULL)
        self.buf:put(string.char(0))  -- NULL 的长度总是0
    end

    --- 编码对象标识符 (OID)
    -- 实现 OID 的 BER 编码算法，将点分OID转换为压缩的VLQ格式
    -- @param oid table OID组件数组，如 {1, 3, 6, 1, 4, 1}
    -- @usage
    -- enc:encode_oid({1, 3, 6, 1, 4, 1})  -- 编码 1.3.6.1.4.1
    function enc:encode_oid(oid)
        self:encode_tag(ber.CLASS_UNIVERSAL, ber.PRIMITIVE, ber.OBJECT_IDENTIFIER)

        if #oid < 2 then
            error("OID must have at least two components")
        end

        -- 编码前两个组件：X * 40 + Y
        local first = oid[1] * 40 + oid[2]
        local oid_data = buffer.new()

        -- 编码第一个字节
        if first > 127 then
            oid_data:put(string.char(bit.bor(0x80, bit.rshift(first, 7))))
        end
        oid_data:put(string.char(bit.band(first, 0x7F)))

        -- 编码剩余组件
        for i = 3, #oid do
            local comp = oid[i]
            if comp < 0 then
                error("OID components cannot be negative")
            end

            local comp_bytes = {}
            while comp > 0 do
                table.insert(comp_bytes, 1, bit.bor(bit.band(comp, 0x7F), 0x80))
                comp = bit.rshift(comp, 7)
            end

            if #comp_bytes == 0 then
                table.insert(comp_bytes, 0)
            else
                comp_bytes[#comp_bytes] = bit.band(comp_bytes[#comp_bytes], 0x7F)
            end

            for _, byte in ipairs(comp_bytes) do
                oid_data:put(string.char(byte))
            end
        end

        self:_encode_length(#oid_data)
        self.buf:put(tostring(oid_data))
    end

    --- 开始序列编码
    -- 开始一个构造序列，返回新的 BER 编码器
    -- @return encoder 用于编码子序列
    -- @usage
    -- local seq = enc:start_sequence()
    -- seq:encode_integer(42)
    -- seq:encode_octet_string("test")
    -- enc:end_sequence(seq)
    function enc:start_sequence()
        -- 返回一个新的子编码器
        return ber.new_encoder()
    end

    --- 结束序列编码
    -- 完成序列编码，计算并写入实际长度
    -- @param encoder seq 将 seq 编码到当前对象中
    -- @usage
    -- local seq = enc:start_sequence()
    -- -- 编码序列内容...
    -- enc:end_sequence(seq)
    function enc:end_sequence(seq)
        assert(seq, "missing sequence encoder")
        local content = seq:get()
        -- 写入 SEQUENCE tag
        self:encode_tag(ber.CLASS_UNIVERSAL, ber.CONSTRUCTED, 16)
        -- 写入长度
        self:_encode_length(#content)
        -- 写入内容
        self.buf:put(content)
    end

    --- 内部方法：在指定缓冲区编码长度
    -- @param buf table string.buffer 实例
    -- @param len number 要编码的长度
    -- @private
    function enc:_encode_length_in_buffer(buf, len)
        if len < 128 then
            buf:put(string.char(len))
        else
            local len_bytes = {}
            while len > 0 do
                table.insert(len_bytes, 1, bit.band(len, 0xFF))
                len = bit.rshift(len, 8)
            end

            buf:put(string.char(bit.bor(0x80, #len_bytes)))
            for _, byte in ipairs(len_bytes) do
                buf:put(string.char(byte))
            end
        end
    end

    --- 获取编码结果
    -- 返回当前缓冲区中的所有编码数据
    -- @return string BER 编码的二进制数据
    function enc:get()
        return tostring(self.buf)
    end

    --- 重置编码器
    -- 清空缓冲区，复用编码器实例
    function enc:reset()
        self.buf:reset()
    end

    --- 编码 BOOLEAN 类型
    -- 将布尔值编码为 BER BOOLEAN 类型
    -- @param val boolean 要编码的布尔值
    -- @usage
    -- enc:encode_boolean(true)
    -- enc:encode_boolean(false)
    function enc:encode_boolean(val)
        self:encode_tag(ber.CLASS_UNIVERSAL, ber.PRIMITIVE, ber.BOOLEAN)
        self:_encode_length(1)
        self.buf:put(string.char(val and 0xFF or 0x00))
    end

    --- 编码 BIT STRING 类型
    -- 将位串编码为 BER BIT STRING 类型
    -- @param data string 位串数据
    -- @param unused_bits number 最后一个字节中未使用的位数 (0-7)，默认为0
    -- @usage
    -- enc:encode_bit_string("\xF0", 4)  -- 编码 1111 (后4位未使用)
    function enc:encode_bit_string(data, unused_bits)
        self:encode_tag(ber.CLASS_UNIVERSAL, ber.PRIMITIVE, ber.BIT_STRING)
        self:_encode_length(#data + 1)
        self.buf:put(string.char(unused_bits or 0))
        self.buf:put(data)
    end

    --- 编码 UTF8 STRING 类型
    -- 将 UTF-8 字符串编码为 BER UTF8String 类型
    -- @param str string UTF-8 编码的字符串
    -- @usage
    -- enc:encode_utf8_string("你好世界")
    function enc:encode_utf8_string(str)
        self:encode_tag(ber.CLASS_UNIVERSAL, ber.PRIMITIVE, ber.UTF8_STRING)
        self:_encode_length(#str)
        self.buf:put(str)
    end

    --- 编码 PrintableString 类型
    -- 将可打印字符串编码为 BER PrintableString 类型
    -- PrintableString 只能包含字母、数字和部分标点符号
    -- @param str string 可打印字符串
    -- @usage
    -- enc:encode_printable_string("Hello World")
    function enc:encode_printable_string(str)
        self:encode_tag(ber.CLASS_UNIVERSAL, ber.PRIMITIVE, ber.PRINTABLE_STRING)
        self:_encode_length(#str)
        self.buf:put(str)
    end

    --- 编码 IA5String 类型
    -- 将 IA5 字符串编码为 BER IA5String 类型
    -- IA5String 等同于 ASCII 字符串
    -- @param str string IA5/ASCII 字符串
    -- @usage
    -- enc:encode_ia5_string("test@example.com")
    function enc:encode_ia5_string(str)
        self:encode_tag(ber.CLASS_UNIVERSAL, ber.PRIMITIVE, ber.IA5_STRING)
        self:_encode_length(#str)
        self.buf:put(str)
    end

    --- 编码 UTC TIME 类型
    -- 将 UTC 时间编码为 BER UTCTime 类型
    -- @param str string UTC 时间字符串，格式为 YYMMDDhhmmssZ
    -- @usage
    -- enc:encode_utc_time("231231235959Z")  -- 2023年12月31日 23:59:59 UTC
    function enc:encode_utc_time(str)
        self:encode_tag(ber.CLASS_UNIVERSAL, ber.PRIMITIVE, ber.UTC_TIME)
        self:_encode_length(#str)
        self.buf:put(str)
    end

    --- 编码 GeneralizedTime 类型
    -- 将通用时间编码为 BER GeneralizedTime 类型
    -- @param str string 通用时间字符串，格式为 YYYYMMDDhhmmssZ
    -- @usage
    -- enc:encode_generalized_time("20231231235959Z")  -- 2023年12月31日 23:59:59 UTC
    function enc:encode_generalized_time(str)
        self:encode_tag(ber.CLASS_UNIVERSAL, ber.PRIMITIVE, ber.GENERALIZED_TIME)
        self:_encode_length(#str)
        self.buf:put(str)
    end

    --- 开始 SET 编码
    -- 开始一个构造集合，返回新的 BER 编码器
    -- @return encoder 用于编码子集合的编码器
    -- @usage
    -- local set = enc:start_set()
    -- set:encode_integer(1)
    -- set:encode_utf8_string("test")
    -- enc:end_set(set)
    function enc:start_set()
        return ber.new_encoder()
    end
    
    --- 结束 SET 编码
    -- 完成集合编码，将子编码器的内容写入当前编码器
    -- @param set_enc encoder start_set 返回的编码器实例
    -- @usage
    -- enc:end_set(set)
    function enc:end_set(set_enc)
        local content = set_enc:get()
        self:encode_tag(ber.CLASS_UNIVERSAL, ber.CONSTRUCTED, 17)
        self:_encode_length(#content)
        self.buf:put(content)
    end
    
    --- 编码带自定义标签的数据
    -- 用于编码 SNMP 等协议中的应用特定或上下文特定类型
    -- @param class number 标签类 (使用 ber.CLASS_* 常量)
    -- @param constructed number 构造标记 (ber.PRIMITIVE 或 ber.CONSTRUCTED)
    -- @param tag_number number 标签编号
    -- @param content string 要编码的内容数据
    -- @usage
    -- enc:encode_with_tag(ber.CLASS_CONTEXT, ber.CONSTRUCTED, 0, pdu_content)
    function enc:encode_with_tag(class, constructed, tag_number, content)
        self:encode_tag(class, constructed, tag_number)
        self:_encode_length(#content)
        self.buf:put(content)
    end
    
    return enc
end



--- 创建新的 BER 解码器
-- @param data string BER 编码的二进制数据
-- @return table 解码器实例，包含解码方法和状态
-- @usage
-- local dec = ber.new_decoder(encoded_data)
-- local value = dec:decode_integer()
function ber.new_decoder(data)
    local dec = {
        buf = buffer.new(),
        pos = 1
    }
    dec.buf:put(data)

    --- 内部方法：读取单个字节
    -- @return number 读取的字节值
    -- @private
    function dec:_read_byte()
        if self.pos > #self.buf then
            error("BER decode: unexpected end of data (buffer overrun)")
        end
        local bufstr = tostring(self.buf)
        local byte = bufstr:byte(self.pos)
        self.pos = self.pos + 1
        return byte
    end

    --- 内部方法：读取指定长度的字节序列
    -- @param len number 要读取的字节数
    -- @return string 读取的字节数据
    -- @private
    function dec:_read_bytes(len)
        if self.pos + len - 1 > #self.buf then
            error("BER decode: unexpected end of data (buffer overrun)")
        end
        local bufstr = tostring(self.buf)
        local data = bufstr:sub(self.pos, self.pos + len - 1)
        self.pos = self.pos + len
        return data
    end

    --- 解码 VLQ (Variable Length Quantity)
    -- 实现变长数量解码算法，用于解码大整数和长标签
    -- @return number 解码后的整数值
    -- @usage
    -- local value = dec:decode_vlq()
    function dec:decode_vlq()
        local value = 0
        local byte

        repeat
            byte = self:_read_byte()
            value = bit.bor(bit.lshift(value, 7), bit.band(byte, 0x7F))
        until bit.band(byte, 0x80) == 0

        return value
    end

    --- 解码长度字段
    -- 根据 BER 长度编码规则解码短格式和长格式
    -- @return number 解码后的长度值，-1 表示不定长度
    -- @usage
    -- local len = dec:decode_length()
    function dec:decode_length()
        local first_byte = self:_read_byte()

        if bit.band(first_byte, 0x80) == 0 then
            -- 短格式：长度直接包含在第一个字节中
            return first_byte
        end

        local num_bytes = bit.band(first_byte, 0x7F)
        if num_bytes == 0 then
            -- 不定长度
            return -1
        end

        -- 长格式：读取后续的长度字节
        local length = 0
        for i = 1, num_bytes do
            length = bit.bor(bit.lshift(length, 8), self:_read_byte())
        end

        return length
    end

    --- 解码 BER 标签
    -- 解析标签的类、构造标记和标签编号
    -- @return table 标签信息表，包含 class, constructed, tag 字段
    -- @usage
    -- local tag_info = dec:decode_tag()
    -- if tag_info.tag == ber.INTEGER then
    --     local value = dec:decode_integer()
    -- end
    function dec:decode_tag()
        local first_byte = self:_read_byte()
        local class = bit.band(first_byte, 0xC0)
        local constructed = bit.band(first_byte, 0x20)
        local tag_number = bit.band(first_byte, 0x1F)

        if tag_number == 0x1F then
            -- 长标签：后续字节包含 VLQ 编码的标签号
            tag_number = self:decode_vlq()
        end

        return {
            class = class,
            constructed = constructed,
            tag = tag_number
        }
    end

    --- 解码整数类型
    -- 实现 BER 整数解码，支持补码表示的负整数
    -- @return number 解码后的整数值
    -- @usage
    -- local value = dec:decode_integer()
    function dec:decode_integer()
        local tag_info = self:decode_tag()

        if tag_info.tag ~= ber.INTEGER then
            error("BER decode: expected INTEGER tag")
        end

        local len = self:decode_length()

        if len <= 0 or len > 8 then
            error("BER decode: invalid INTEGER length")
        end

        local data = self:_read_bytes(len)

        local value = 0
        local negative = false

        local bufstr = data
        -- 检查符号位（最高字节的最高位）
        if bit.band(bufstr:byte(1), 0x80) ~= 0 then
            negative = true
        end

        -- 解码整数值
        for i = 1, #data do
            local byte = data:byte(i)
            if negative then
                -- 负数使用补码，需要先取反
                byte = bit.bnot(byte) % 256
            end
            value = bit.bor(bit.lshift(value, 8), byte)
        end

        if negative then
            value = -(value + 1)  -- 补码转原码：取反加1后取负
        end


        return value
    end

    --- 解码八位字节串类型
    -- @return string 解码后的二进制数据
    -- @usage
    -- local data = dec:decode_octet_string()
    function dec:decode_octet_string()
        local tag_info = self:decode_tag()
        if tag_info.tag ~= ber.OCTET_STRING then
            error("BER decode: expected OCTET_STRING tag")
        end

        local len = self:decode_length()
        if len < 0 or len > 65536 then
            error("BER decode: invalid OCTET_STRING length")
        end

        return self:_read_bytes(len)
    end

    --- 解码 NULL 类型
    -- @return boolean 总是返回 true
    -- @usage
    -- dec:decode_null()
    function dec:decode_null()
        local tag_info = self:decode_tag()
        if tag_info.tag ~= ber.NULL then
            error("BER decode: expected NULL tag")
        end

        local len = self:decode_length()
        if len ~= 0 then
            error("BER decode: NULL must have zero length")
        end

        return true
    end

    --- 解码对象标识符 (OID)
    -- 实现 OID 的 BER 解码算法，将压缩的VLQ格式转换为点分OID
    -- @return table OID组件数组
    -- @usage
    -- local oid = dec:decode_oid()
    -- print(table.concat(oid, "."))  -- 输出 "1.3.6.1.4.1"
    function dec:decode_oid()
        local tag_info = self:decode_tag()
        if tag_info.tag ~= ber.OBJECT_IDENTIFIER then
            error("BER decode: expected OBJECT_IDENTIFIER tag")
        end

        local len = self:decode_length()
        if len <= 0 or len > 128 then
            error("BER decode: invalid OID length")
        end

        local data = self:_read_bytes(len)
        local oid = {}
        local pos = 1
        local bufstr = data
        -- 解码第一个字节（包含前两个组件）
        if pos > #bufstr then
            error("BER decode: incomplete OID data")
        end

        local first_byte = bufstr:byte(pos)
        pos = pos + 1

        -- 第一个字节包含两个组件：X = first_byte / 40, Y = first_byte % 40
        table.insert(oid, math.floor(first_byte / 40))
        table.insert(oid, first_byte % 40)

        -- 解码剩余组件
        while pos <= #bufstr do
            local value = 0
            local byte

            repeat
                if pos > #bufstr then
                    error("BER decode: incomplete OID component")
                end
                byte = bufstr:byte(pos)
                pos = pos + 1
                value = bit.bor(bit.lshift(value, 7), bit.band(byte, 0x7F))
            until bit.band(byte, 0x80) == 0

            table.insert(oid, value)
        end

        return oid
    end

    --- 开始序列解码
    -- 开始解码一个构造序列，返回序列结束位置
    -- @return number 序列结束位置，用于 at_sequence_end
    -- @usage
    -- local end_pos = dec:start_sequence()
    -- while not dec:at_sequence_end(end_pos) do
    --     -- 解码序列元素...
    -- end
    function dec:start_sequence()
        local tag_info = self:decode_tag()
        if tag_info.tag ~= 16 or tag_info.constructed == 0 then
            error("BER decode: expected SEQUENCE tag")
        end

        local len = self:decode_length()
        if len < 0 then
            error("BER decode: indefinite length sequences not supported")
        end

        local end_pos = self.pos + len
        return end_pos
    end

    --- 检查是否到达序列末尾
    -- @param end_pos number start_sequence 返回的结束位置
    -- @return boolean 如果到达序列末尾返回 true
    function dec:at_sequence_end(end_pos)
        return self.pos >= end_pos
    end

    --- 获取当前解码位置
    -- @return number 当前在输入数据中的位置
    function dec:get_position()
        return self.pos
    end

    --- 设置解码位置
    -- 用于回退或跳转到特定位置
    -- @param pos number 要设置的位置
    function dec:set_position(pos)
        self.pos = pos
    end

    --- 获取剩余数据长度
    -- @return number 剩余未解码的字节数
    function dec:remaining()
        return #self.buf - self.pos + 1
    end

    --- 解码 BOOLEAN 类型
    -- 从 BER 数据中解码布尔值
    -- @return boolean 解码后的布尔值
    -- @usage
    -- local value = dec:decode_boolean()
    function dec:decode_boolean()
        local tag_info = self:decode_tag()
        if tag_info.tag ~= ber.BOOLEAN then error("BER decode: expected BOOLEAN tag") end
        local len = self:decode_length()
        assert(len == 1, "BER BOOLEAN length must be 1")
        local v = self:_read_byte()
        return v ~= 0
    end

    --- 解码 BIT STRING 类型
    -- 从 BER 数据中解码位串
    -- @return string 位串数据
    -- @return number 最后一个字节中未使用的位数 (0-7)
    -- @usage
    -- local data, unused_bits = dec:decode_bit_string()
    function dec:decode_bit_string()
        local tag_info = self:decode_tag()
        if tag_info.tag ~= ber.BIT_STRING then error("BER decode: expected BIT_STRING tag") end
        local len = self:decode_length()
        local unused = self:_read_byte()
        local data = self:_read_bytes(len - 1)
        return data, unused
    end

    --- 解码 UTF8 STRING 类型
    -- 从 BER 数据中解码 UTF-8 字符串
    -- @return string UTF-8 编码的字符串
    -- @usage
    -- local str = dec:decode_utf8_string()
    function dec:decode_utf8_string()
        local tag_info = self:decode_tag()
        if tag_info.tag ~= ber.UTF8_STRING then error("BER decode: expected UTF8_STRING tag") end
        local len = self:decode_length()
        return self:_read_bytes(len)
    end

    --- 解码 PrintableString 类型
    -- 从 BER 数据中解码可打印字符串
    -- @return string 可打印字符串
    -- @usage
    -- local str = dec:decode_printable_string()
    function dec:decode_printable_string()
        local tag_info = self:decode_tag()
        if tag_info.tag ~= ber.PRINTABLE_STRING then error("BER decode: expected PRINTABLE_STRING tag") end
        local len = self:decode_length()
        return self:_read_bytes(len)
    end

    --- 解码 IA5String 类型
    -- 从 BER 数据中解码 IA5/ASCII 字符串
    -- @return string IA5 字符串
    -- @usage
    -- local str = dec:decode_ia5_string()
    function dec:decode_ia5_string()
        local tag_info = self:decode_tag()
        if tag_info.tag ~= ber.IA5_STRING then error("BER decode: expected IA5_STRING tag") end
        local len = self:decode_length()
        return self:_read_bytes(len)
    end

    --- 解码 UTC TIME 类型
    -- 从 BER 数据中解码 UTC 时间
    -- @return string UTC 时间字符串，格式为 YYMMDDhhmmssZ
    -- @usage
    -- local time = dec:decode_utc_time()
    function dec:decode_utc_time()
        local tag_info = self:decode_tag()
        if tag_info.tag ~= ber.UTC_TIME then error("BER decode: expected UTC_TIME tag") end
        local len = self:decode_length()
        return self:_read_bytes(len)
    end

    --- 解码 GeneralizedTime 类型
    -- 从 BER 数据中解码通用时间
    -- @return string 通用时间字符串，格式为 YYYYMMDDhhmmssZ
    -- @usage
    -- local time = dec:decode_generalized_time()
    function dec:decode_generalized_time()
        local tag_info = self:decode_tag()
        if tag_info.tag ~= ber.GENERALIZED_TIME then error("BER decode: expected GENERALIZED_TIME tag") end
        local len = self:decode_length()
        return self:_read_bytes(len)
    end

    --- 开始 SET 解码
    -- 开始解码一个构造集合，返回集合结束位置
    -- @return number 集合结束位置，用于 at_sequence_end 检查
    -- @usage
    -- local end_pos = dec:start_set()
    -- while not dec:at_sequence_end(end_pos) do
    --     -- 解码集合元素...
    -- end
    function dec:start_set()
        local tag_info = self:decode_tag()
        if tag_info.tag ~= 17 or tag_info.constructed == 0 then
            error("BER decode: expected SET tag")
        end
        local len = self:decode_length()
        return self.pos + len
    end
    return dec
end



--- 便捷函数：编码整数
-- @param value number 要编码的整数值
-- @return string BER 编码的整数数据
-- @usage
-- local data = ber.encode_integer(42)
function ber.encode_integer(value)
    local enc = ber.new_encoder()
    enc:encode_integer(value)
    return enc:get()
end

--- 便捷函数：解码整数
-- @param data string BER 编码的整数数据
-- @return number 解码后的整数值
-- @usage
-- local value = ber.decode_integer(data)
function ber.decode_integer(data)
    local dec = ber.new_decoder(data)
    return dec:decode_integer()
end

--- 便捷函数：编码 OID
-- @param oid table OID组件数组
-- @return string BER 编码的 OID 数据
-- @usage
-- local data = ber.encode_oid({1, 3, 6, 1, 4, 1})
function ber.encode_oid(oid)
    local enc = ber.new_encoder()
    enc:encode_oid(oid)
    return enc:get()
end

--- 便捷函数：解码 OID
-- @param data string BER 编码的 OID 数据
-- @return table OID组件数组
-- @usage
-- local oid = ber.decode_oid(data)
-- print("OID:", table.concat(oid, "."))
function ber.decode_oid(data)
    local dec = ber.new_decoder(data)
    return dec:decode_oid()
end

return ber
