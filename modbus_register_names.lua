-- Debug flag: set to true to enable debug output in Wireshark console
local DEBUG = false

if DEBUG then print("Modbus register script loaded!") end

local modbus_names = Proto("modbus_names", "Modbus Register Info")

----------------------------------------------------------------------
--  REGISTER DEFINITIONS
----------------------------------------------------------------------

local register_info = {
    -- PV Array
    [0x3100] = { name="PV Array Input Voltage",      scale=0.01, unit="V",   bits=16, signed=false },
    [0x3101] = { name="PV Array Input Current",      scale=0.01, unit="A",   bits=16, signed=false },
    [0x3102] = { name="PV Array Input Power (L)",    scale=0.01, unit="W",   bits=32, signed=false },
    [0x3103] = { name="PV Array Input Power (H)",    scale=0.01, unit="W",   bits=32, signed=false },

    -- Battery realtime
    [0x3106] = { name="Battery Power (L)",           scale=0.01, unit="W",   bits=32, signed=false },
    [0x3107] = { name="Battery Power (H)",           scale=0.01, unit="W",   bits=32, signed=false },

    [0x3110] = { name="Battery Temperature",         scale=0.01, unit="°C",  bits=16, signed=true  },
    [0x311A] = { name="Battery State of Charge",     scale=1,    unit="%",   bits=16, signed=false },
    [0x311B] = { name="Remote Battery Temperature",  scale=0.01, unit="°C",  bits=16, signed=true  },
    [0x311D] = { name="Battery Real Rated Voltage",  scale=0.01, unit="V",   bits=16, signed=false },

    -- Battery voltage/current (newer models)
    [0x331A] = { name="Battery Voltage",             scale=0.01, unit="V",   bits=16, signed=false },
    [0x331B] = { name="Battery Current (L)",         scale=0.01, unit="A",   bits=32, signed=true  },
    [0x331C] = { name="Battery Current (H)",         scale=0.01, unit="A",   bits=32, signed=true  },

    -- Load
    [0x310C] = { name="Load Voltage",                scale=0.01, unit="V",   bits=16, signed=false },
    [0x310D] = { name="Load Current",                scale=0.01, unit="A",   bits=16, signed=false },
    [0x310E] = { name="Load Power (L)",              scale=0.01, unit="W",   bits=32, signed=false },
    [0x310F] = { name="Load Power (H)",              scale=0.01, unit="W",   bits=32, signed=false },

    -- Historical (today)
    [0x3300] = { name="Max PV Voltage Today",        scale=0.01, unit="V",   bits=16, signed=false },
    [0x3301] = { name="Min PV Voltage Today",        scale=0.01, unit="V",   bits=16, signed=false },
    [0x3302] = { name="Max Battery Voltage Today",   scale=0.01, unit="V",   bits=16, signed=false },
    [0x3303] = { name="Min Battery Voltage Today",   scale=0.01, unit="V",   bits=16, signed=false },

    [0x3304] = { name="Consumed Energy Today (L)",   scale=0.01, unit="kWh", bits=32, signed=false },
    [0x3305] = { name="Consumed Energy Today (H)",   scale=0.01, unit="kWh", bits=32, signed=false },

    [0x330C] = { name="Generated Energy Today (L)",  scale=0.01, unit="kWh", bits=32, signed=false },
    [0x330D] = { name="Generated Energy Today (H)",  scale=0.01, unit="kWh", bits=32, signed=false },

    -- Historical (month/year)
    [0x3306] = { name="Consumed Energy This Month (L)", scale=0.01, unit="kWh", bits=32, signed=false },
    [0x3307] = { name="Consumed Energy This Month (H)", scale=0.01, unit="kWh", bits=32, signed=false },

    [0x3308] = { name="Consumed Energy This Year (L)",  scale=0.01, unit="kWh", bits=32, signed=false },
    [0x3309] = { name="Consumed Energy This Year (H)",  scale=0.01, unit="kWh", bits=32, signed=false },

    [0x330A] = { name="Total Consumed Energy (L)",      scale=0.01, unit="kWh", bits=32, signed=false },
    [0x330B] = { name="Total Consumed Energy (H)",      scale=0.01, unit="kWh", bits=32, signed=false },

    [0x330E] = { name="Generated Energy This Month (L)", scale=0.01, unit="kWh", bits=32, signed=false },
    [0x330F] = { name="Generated Energy This Month (H)", scale=0.01, unit="kWh", bits=32, signed=false },

    [0x3310] = { name="Generated Energy This Year (L)",  scale=0.01, unit="kWh", bits=32, signed=false },
    [0x3311] = { name="Generated Energy This Year (H)",  scale=0.01, unit="kWh", bits=32, signed=false },

    [0x3312] = { name="Total Generated Energy (L)",      scale=0.01, unit="kWh", bits=32, signed=false },
    [0x3313] = { name="Total Generated Energy (H)",      scale=0.01, unit="kWh", bits=32, signed=false },

    -- Status registers
    [0x3200] = { name="Battery Status",               scale=1, unit="", bits=16, signed=false },
    [0x3201] = { name="Charging Equipment Status",    scale=1, unit="", bits=16, signed=false },
    [0x3202] = { name="Discharging Equipment Status", scale=1, unit="", bits=16, signed=false },
}

----------------------------------------------------------------------
--  DISCRETE INPUT DEFINITIONS (Function Code 2)
--  These are individual bits, not 16-bit registers
----------------------------------------------------------------------

local discrete_inputs = {
    -- Example: Define your discrete inputs starting at 0x2000
    [0x2000] = { name="Discrete Input 1", description="Status bit 1" },
    [0x2001] = { name="Discrete Input 2", description="Status bit 2" },
    [0x2002] = { name="Discrete Input 3", description="Status bit 3" },
    [0x2003] = { name="Discrete Input 4", description="Status bit 4" },
    [0x2004] = { name="Discrete Input 5", description="Status bit 5" },
    [0x2005] = { name="Discrete Input 6", description="Status bit 6" },
    [0x2006] = { name="Discrete Input 7", description="Status bit 7" },
    [0x2007] = { name="Discrete Input 8", description="Status bit 8" },
    -- Add more as needed
}

----------------------------------------------------------------------
--  BITMAPPED REGISTER DEFINITIONS
----------------------------------------------------------------------

local bitfields = {
    [0x2000] = {
        { mask=0x8000, shift=15, name="0x2000 bit 15 not in use", values={[0]="0",[1]="1"} },
        { mask=0x4000, shift=14, name="0x2000 bit 14 not in use", values={[0]="0",[1]="1"} },
        { mask=0x2000, shift=13, name="0x2000 bit 13 not in use", values={[0]="0",[1]="1"} },
        { mask=0x1000, shift=12, name="0x2000 bit 12 not in use", values={[0]="0",[1]="1"} },
        { mask=0x0800, shift=11, name="0x2000 bit 11 not in use", values={[0]="0",[1]="1"} },
        { mask=0x0400, shift=10, name="0x2000 bit 10 not in use", values={[0]="0",[1]="1"} },
        { mask=0x0200, shift=9,  name="0x2000 bit 9 not in use",  values={[0]="0",[1]="1"} },
        { mask=0x0100, shift=8,  name="0x2000 bit 8 not in use",  values={[0]="0",[1]="1"} },
        { mask=0x0080, shift=7,  name="0x2000 bit 7 not in use",  values={[0]="0",[1]="1"} },
        { mask=0x0040, shift=6,  name="0x2000 bit 6 not in use",  values={[0]="0",[1]="1"} },
        { mask=0x0020, shift=5,  name="0x2000 bit 5 not in use",  values={[0]="0",[1]="1"} },
        { mask=0x0010, shift=4,  name="0x2000 bit 4 not in use",  values={[0]="0",[1]="1"} },
        { mask=0x0008, shift=3,  name="0x2000 bit 3 not in use",  values={[0]="0",[1]="1"} },
        { mask=0x0004, shift=2,  name="0x2000 bit 2 not in use",  values={[0]="0",[1]="1"} },
        { mask=0x0002, shift=1,  name="0x2000 bit 1 not in use",  values={[0]="0",[1]="1"} },
        { mask=0x0001, shift=0,  name="Over Temperature",  values={[0]="No",[1]="Yes"} },
    }, 
    [0x3200] = {
        { mask=0x8000, shift=15, name="Wrong rated voltage ID", values={[0]="NO",[1]="YES"} },
        { mask=0x0100, shift=8,  name="Battery inner resistance abnormal", values={[0]="NO",[1]="YES"} },
        { mask=0x00F0, shift=4,  name="Temperature warning", values={[0]="NORMAL",[1]="OVER_TEMP",[2]="LOW_TEMP"} },
        { mask=0x000F, shift=0,  name="Battery status", values={[0]="NORMAL",[1]="OVER_VOLTAGE",[2]="UNDER_VOLTAGE",[3]="OVER_DISCHARGE",[4]="FAULT"} },
    },

    [0x3201] = {
        { mask=0xC000, shift=14, name="Input voltage status", values={[0]="NORMAL",[1]="NO_INPUT_POWER",[2]="HIGHER_INPUT",[3]="INPUT_VOLTAGE_ERROR"} },
        { mask=0x2000, shift=13, name="Charging MOSFET short", values={[0]="NO",[1]="YES"} },
        { mask=0x1000, shift=12, name="Anti-reverse MOSFET open", values={[0]="NO",[1]="YES"} },
        { mask=0x0800, shift=11, name="Anti-reverse MOSFET short", values={[0]="NO",[1]="YES"} },
        { mask=0x0400, shift=10, name="Input over current", values={[0]="NO",[1]="YES"} },
        { mask=0x0200, shift=9,  name="Load over current", values={[0]="NO",[1]="YES"} },
        { mask=0x0100, shift=8,  name="Load short circuit", values={[0]="NO",[1]="YES"} },
        { mask=0x0080, shift=7,  name="Load MOSFET short", values={[0]="NO",[1]="YES"} },
        { mask=0x0040, shift=6,  name="Circuit imbalance", values={[0]="NO",[1]="YES"} },
        { mask=0x0010, shift=4,  name="PV input short", values={[0]="NO",[1]="YES"} },
        { mask=0x000C, shift=2,  name="Charging status", values={[0]="NO_CHARGING",[1]="FLOAT",[2]="BOOST",[3]="EQUALIZATION"} },
        { mask=0x0002, shift=1,  name="Fault", values={[0]="NO",[1]="YES"} },
        { mask=0x0001, shift=0,  name="Running", values={[0]="NO",[1]="YES"} },
    },

    [0x3202] = {
        { mask=0xC000, shift=14, name="Input voltage status", values={[0]="NORMAL",[1]="LOW",[2]="HIGH",[3]="NO_ACCESS"} },
        { mask=0x3000, shift=12, name="Output power load", values={[0]="LIGHT",[1]="MODERATE",[2]="RATED",[3]="OVERLOAD"} },
        { mask=0x0800, shift=11, name="Short circuit", values={[0]="NO",[1]="YES"} },
        { mask=0x0400, shift=10, name="Unable to discharge", values={[0]="NO",[1]="YES"} },
        { mask=0x0200, shift=9,  name="Unable to stop discharging", values={[0]="NO",[1]="YES"} },
        { mask=0x0100, shift=8,  name="Output voltage abnormal", values={[0]="NO",[1]="YES"} },
        { mask=0x0080, shift=7,  name="Input over voltage", values={[0]="NO",[1]="YES"} },
        { mask=0x0040, shift=6,  name="High-side short", values={[0]="NO",[1]="YES"} },
        { mask=0x0020, shift=5,  name="Boost over voltage", values={[0]="NO",[1]="YES"} },
        { mask=0x0010, shift=4,  name="Output over voltage", values={[0]="NO",[1]="YES"} },
        { mask=0x0002, shift=1,  name="Fault", values={[0]="NO",[1]="YES"} },
        { mask=0x0001, shift=0,  name="Running", values={[0]="NO",[1]="YES"} },
    },
}

----------------------------------------------------------------------
--  PROTO FIELDS
----------------------------------------------------------------------

local pf_name  = ProtoField.string("modbus_names.register_name", "Register Name")
local pf_value = ProtoField.string("modbus_names.scaled_value", "Scaled Value")

modbus_names.fields = { pf_name, pf_value }

----------------------------------------------------------------------
--  HELPERS
----------------------------------------------------------------------
--mbrtu.unit_id
--modbus.func_code
--modbus.byte_cnt
--modbus.regval_uint16
--mbrtu.crc16

-- Store reference numbers from query packets by frame number
local query_refs = {}

local f_ref  = Field.new("modbus.reference_num")
local f_func = Field.new("modbus.func_code")
local f_byte_cnt = Field.new("modbus.byte_cnt")  -- Only exists in response packets
local f_request_frame = nil  -- Will try to get this if it exists
local f_register_num = nil  -- Register number in response packets

-- Try to get request frame field
local status, req_frame_field = pcall(Field.new, "modbus.request_frame")
if status then
    f_request_frame = req_frame_field
end

-- Try to get register number field (might exist in responses)
local status2, reg_num_field = pcall(Field.new, "modbus.register_num")
if status2 then
    f_register_num = reg_num_field
end

-- Try multiple possible field names for register data at TOP LEVEL
local f_data_candidates = {}
local field_names_to_try = {
    "modbus.data",
    "modbus.regval_uint16",
    "modbus.register",
    "modbus.value",
    "modbus.word_data",
    "mbrtu.data",
    "modbus.bitval"
}

for _, fname in ipairs(field_names_to_try) do
    local status, fld = pcall(Field.new, fname)
    if status then
        f_data_candidates[fname] = fld
        if DEBUG then print("Registered field extractor for: "..fname) end
    end
end

local function to_signed16(v)
    return v >= 0x8000 and (v - 0x10000) or v
end

local function to_signed32(v)
    return v >= 0x80000000 and (v - 0x100000000) or v
end

local function hex_fmt(v, bits)
    return bits == 32 and string.format("0x%08X", v) or string.format("0x%04X", v)
end

----------------------------------------------------------------------
--  MAIN DISSECTOR
----------------------------------------------------------------------


function modbus_names.dissector(tvb, pinfo, tree)
    --     pinfo.cols.info:set("")
    -- f_ref and f_data are now always initialized at the top level
    
    if DEBUG then
        print("========== DISSECTOR CALLED FOR PACKET ==========")
        print("Packet number: "..pinfo.number)
        print("Packet info: "..tostring(pinfo.cols.info))
    end

    -- Check function code first
    local func_field = f_func()
    if not func_field then 
        if DEBUG then print("No function code found") end
        return 
    end
    local func_code = tonumber(tostring(func_field))
    if DEBUG then print("Function code: "..func_code) end
    
    -- Support Read Discrete Inputs (2) and Read Input Registers (4)
    if func_code ~= 2 and func_code ~= 4 then
        if DEBUG then print("Not a Read Discrete Inputs or Read Input Registers packet, skipping") end
        return
    end

    -- Determine if this is a Query or Response
    local byte_cnt_field = f_byte_cnt()
    local is_response = (byte_cnt_field ~= nil)
    if DEBUG then print("Packet type: "..(is_response and "Response" or "Query")) end

    local ref = nil
    
    if not is_response then
        -- This is a Query packet - extract and store reference number
        local ref_field = f_ref()
        if not ref_field then
            if DEBUG then print("No reference_num in Query packet") end
            return
        end
        ref = tonumber(tostring(ref_field))
        if DEBUG then print("Query reference number: "..string.format("0x%04X", ref)) end
        
        -- Store for later use by response
        query_refs[pinfo.number] = ref
        if DEBUG then print("Stored reference "..string.format("0x%04X", ref).." for frame "..pinfo.number) end
        
        -- Add register info to Query packet Info column
        if func_code == 2 then
            -- Discrete Input
            local di_info = discrete_inputs[ref]
            if di_info then
                pinfo.cols.info:append(string.format(" [Ref=0x%04X] [%s]", ref, di_info.name))
            else
                pinfo.cols.info:append(string.format(" [Ref=0x%04X]", ref))
            end
        else
            -- Input Register
            local info = register_info[ref]
            if info then
                pinfo.cols.info:append(string.format(" [Ref=0x%04X] [%s]", ref, info.name))
            else
                pinfo.cols.info:append(string.format(" [Ref=0x%04X]", ref))
            end
        end
        
        -- Don't process Query packets further
        return
    else
        -- This is a Response packet - look up reference from request
        if not f_request_frame then
            if DEBUG then print("Cannot find request frame field") end
            return
        end
        
        local req_frame_field = f_request_frame()
        if not req_frame_field then
            if DEBUG then print("No request frame link in response") end
            return
        end
        
        local req_frame_num = tonumber(tostring(req_frame_field))
        if DEBUG then print("Request frame number: "..req_frame_num) end
        
        -- Look up stored reference
        ref = query_refs[req_frame_num]
        if not ref then
            if DEBUG then print("No stored reference found for request frame "..req_frame_num) end
            return
        end
        if DEBUG then print("Retrieved reference number: "..string.format("0x%04X", ref)) end
    end

    -- Now process the response with the reference number
    if DEBUG then print("Reference number found: "..string.format("0x%04X", ref)) end

    -- Handle Discrete Inputs (function code 2) differently
    if func_code == 2 then
        if DEBUG then print("Processing Discrete Inputs response") end
        -- For discrete inputs, we get packed bits
        -- Try to find the data field (might be modbus.data or similar)
        local found_data = nil
        for fname, fld in pairs(f_data_candidates) do
            local vals = { fld() }
            if #vals > 0 then
                if DEBUG then print("  FOUND DATA for discrete inputs: "..fname) end
                found_data = vals[1]
                break
            end
        end
        
        if not found_data then
            if DEBUG then print("No data found for discrete inputs") end
            return
        end
        
        -- Create subtree
        local root = tree:add(modbus_names, tvb(0, -1), "Modbus Discrete Inputs")
        
        -- Convert data to string and extract bytes
        local data_str = tostring(found_data)
        local byte_array = ByteArray.new(data_str)
        local num_bytes = byte_array:len()
        if DEBUG then print("Discrete input data: "..num_bytes.." bytes") end
        
        -- Check if we have bitfield definitions for this address range
        local bf = bitfields[ref]
        
        if bf and num_bytes <= 2 then
            -- Use bitfield definitions (for up to 16 bits)
            local word_val = byte_array:get_index(0)
            if num_bytes == 2 then
                word_val = word_val + (byte_array:get_index(1) << 8)
            end
            
            root:add(string.format("Address: 0x%04X, Value: 0x%04X", ref, word_val))
            
            for _, field in ipairs(bf) do
                local bitval = (word_val & field.mask) >> field.shift
                local text = field.values[bitval] or ("Unknown ("..bitval..")")
                root:add(string.format("%s: %s", field.name, text))
                pinfo.cols.info:append(string.format(" [%s=%s]", field.name, text))
            end
        else
            -- Generic bit unpacking (no bitfield definitions)
            for byte_idx = 0, num_bytes - 1 do
                local byte_val = byte_array:get_index(byte_idx)
                for bit_idx = 0, 7 do
                    local bit_addr = ref + (byte_idx * 8) + bit_idx
                    local bit_val = (byte_val >> bit_idx) & 1
                    local di_info = discrete_inputs[bit_addr]
                    
                    if di_info then
                        local status = (bit_val == 1) and "ON" or "OFF"
                        root:add(string.format("[0x%04X] %s: %s", bit_addr, di_info.name, status))
                        pinfo.cols.info:append(string.format(" [%s=%s]", di_info.name, status))
                    else
                        root:add(string.format("[0x%04X] = %d", bit_addr, bit_val))
                    end
                end
            end
        end
        
        return  -- Done processing discrete inputs
    end

    -- Handle Input Registers (function code 4)
    -- Now check which field extractors actually find data in THIS packet
    if DEBUG then print("=== CHECKING WHICH FIELDS HAVE DATA ===") end
    local found_field_name = nil
    local found_values = nil
    
    for fname, fld in pairs(f_data_candidates) do
        local vals = { fld() }
        if #vals > 0 then
            if DEBUG then print("  FOUND DATA: "..fname.." has "..#vals.." values, first value: "..tostring(vals[1])) end
            if not found_field_name then
                found_field_name = fname
                found_values = vals
            end
        else
            if DEBUG then print("  No data in: "..fname) end
        end
    end
    if DEBUG then print("=== END OF CHECK ===") end

    if not found_field_name then
        if DEBUG then print("ERROR: No register data fields found in this packet") end
        return
    end
    
    if DEBUG then print("Using field: "..found_field_name.." with "..#found_values.." values") end

    -- One subtree for all registers
    local root = tree:add(modbus_names, tvb(0, -1), "Modbus Register Details")

    -- Process each register value
    for i, val in ipairs(found_values) do
        local addr = ref + (i - 1)
        local raw16 = tonumber(tostring(val))
        
        root:add(string.format("Reference Number (hex): 0x%04X", addr))
        pinfo.cols.info:append(string.format(" [Ref=0x%04X]", addr))
        
        local info = register_info[addr]

        if info then
            local hex = hex_fmt(raw16, 16)
            local scaled = raw16 * info.scale
            local scaled_str = string.format("%.2f %s", scaled, info.unit)

            -- Add to Info column
            pinfo.cols.info:append(string.format(
                " [%s = %s (%s)]",
                info.name, hex, scaled_str
            ))

            -- Add to tree
            root:add(pf_name, info.name)
            root:add(pf_value, string.format("%s (%s)", hex, scaled_str))

            -- Bitmapped decode
            local bf = bitfields[addr]
            if bf then
                local btree = root:add(string.format("%s Flags (%s)", info.name, hex))
                for _, field in ipairs(bf) do
                    local bitval = (raw16 & field.mask) >> field.shift
                    local text = field.values[bitval] or ("Unknown ("..bitval..")")
                    btree:add(string.format("%s: %s", field.name, text))
                end
            end
        else
            -- Unknown register
            root:add(string.format("0x%04X = 0x%04X", addr, raw16))
        end
    end
end

register_postdissector(modbus_names)
