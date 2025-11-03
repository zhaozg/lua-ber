-- 编码示例
local ber = require('ber')
local enc = ber.new_encoder()
local seq = enc:start_sequence()
seq:encode_integer(42)
seq:encode_octet_string("hello")
seq:encode_oid({1, 3, 6, 1, 4, 1})
enc:end_sequence(seq)
local encoded_data = enc:get()
print(encoded_data)



-- 解码示例
local dec = ber.new_decoder(encoded_data)
local end_pos = dec:start_sequence()
while not dec:at_sequence_end(end_pos) do
    local pos = dec:get_position()
    local tag_info = dec:decode_tag()
    dec:set_position(pos) -- 回退到tag位置

    if tag_info.tag == ber.INTEGER then
        print("Integer:", dec:decode_integer())
    elseif tag_info.tag == ber.OCTET_STRING then
        print("String:", dec:decode_octet_string())
    elseif tag_info.tag == ber.OBJECT_IDENTIFIER then
        print("OID:", table.concat(dec:decode_oid(), "."))
    else
        error("Unknown tag: " .. tostring(tag_info.tag))
    end
end
