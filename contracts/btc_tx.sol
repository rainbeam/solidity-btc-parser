// Bitcoin transaction parsing library

// https://en.bitcoin.it/wiki/Protocol_documentation#tx
//
// Raw Bitcoin transaction structure:
//
// field     | size | type     | description
// version   | 4    | int32    | transaction version number
// n_tx_in   | 1-9  | var_int  | number of transaction inputs
// tx_in     | 41+  | tx_in[]  | list of transaction inputs
// n_tx_out  | 1-9  | var_int  | number of transaction outputs
// tx_out    | 9+   | tx_out[] | list of transaction outputs
// lock_time | 4    | uint32   | block number / timestamp at which tx locked
//
// Transaction input (tx_in) structure:
//
// field      | size | type     | description
// previous   | 36   | outpoint | Previous output transaction reference
// script_len | 1-9  | var_int  | Length of the signature script
// sig_script | ?    | uchar[]  | Script for confirming transaction authorization
// sequence   | 4    | uint32   | Sender transaction version
//
// OutPoint structure:
//
// field      | size | type     | description
// hash       | 32   | char[32] | The hash of the referenced transaction
// index      | 4    | uint32   | The index of this output in the referenced transaction
//
// Transaction output (tx_out) structure:
//
// field         | size | type     | description
// value         | 8    | int64    | Transaction value (Satoshis)
// pk_script_len | 1-9  | var_int  | Length of the public key script
// pk_script     | ?    | uchar[]  | Public key as a Bitcoin script.
//
// Variable integers (var_int) can be encoded differently depending
// on the represented value, to save space. Variable integers always
// precede an array of a variable length data type (e.g. tx_in).
//
// Variable integer encodings as a function of represented value:
//
// value           | bytes  | format
// <0xFD (253)     | 1      | uint8
// <=0xFFFF (65535)| 3      | 0xFD followed by length as uint16
// <=0xFFFF FFFF   | 5      | 0xFE followed by length as uint32
// -               | 9      | 0xFF followed by length as uint64

// parse a raw bitcoin transaction byte array
library BTC {
    uint constant BYTES_1 = 2 ** 8;
    uint constant BYTES_2 = 2 ** 16;
    uint constant BYTES_3 = 2 ** 24;
    uint constant BYTES_4 = 2 ** 32;
    uint constant BYTES_5 = 2 ** 40;
    uint constant BYTES_6 = 2 ** 48;
    uint constant BYTES_7 = 2 ** 56;
    // Convert a variable integer into something useful and return it and
    // the index to after it.
    function parseVarInt(bytes txBytes, uint pos) returns (uint, uint) {
        // the first byte tells us how big the integer is
        var ibit = uint8(txBytes[pos]);
        pos += 1;  // skip ibit

        if (ibit < 0xfd) {
            return (ibit, pos);
        } else if (ibit == 0xfd) {
            return (getBytesLE(txBytes, pos, 16), pos + 3);
        } else if (ibit == 0xfe) {
            return (getBytesLE(txBytes, pos, 32), pos + 5);
        } else if (ibit == 0xff) {
            return (getBytesLE(txBytes, pos, 64), pos + 9);
        }
    }
    // convert little endian bytes to uint
    function getBytesLE(bytes data, uint pos, uint bits) returns (uint) {
        if (bits == 16) {
            return uint16(data[pos])
                 + uint16(data[pos + 1]) * BYTES_1;
        } else if (bits == 32) {
            return uint32(data[pos])
                 + uint32(data[pos + 1]) * BYTES_1
                 + uint32(data[pos + 2]) * BYTES_2
                 + uint32(data[pos + 3]) * BYTES_3;
        } else if (bits == 64) {
            return uint64(data[pos])
                 + uint64(data[pos + 1]) * BYTES_1
                 + uint64(data[pos + 2]) * BYTES_2
                 + uint64(data[pos + 3]) * BYTES_3
                 + uint64(data[pos + 4]) * BYTES_4
                 + uint64(data[pos + 5]) * BYTES_5
                 + uint64(data[pos + 6]) * BYTES_6
                 + uint64(data[pos + 7]) * BYTES_7;
        }
    }
    function getFirstTwoOutputs(bytes txBytes)
             returns (uint, uint, uint, uint)
    {
        uint pos;
        uint[] memory input_script_lens;
        uint[] memory output_script_lens;
        uint[] memory output_values;

        pos = 4;  // skip version

        (input_script_lens, pos) = scanInputs(txBytes, pos, 0);

        (output_values, output_script_lens, pos) = scanOutputs(txBytes, pos, 2);

        return (output_values[0], output_script_lens[0],
                output_values[1], output_script_lens[1]);
    }
    // scan the inputs and find the script lengths.
    // return an array of script lengths and the end position
    // of the inputs.
    // takes a 'stop' argument which sets how many inputs to
    // scan through. stop=0 => scan all.
    function scanInputs(bytes txBytes, uint pos, uint stop)
             returns (uint[], uint)
    {
        uint n_inputs;
        uint halt;
        uint script_len;

        (n_inputs, pos) = parseVarInt(txBytes, pos);

        if (stop == 0) {
            halt = n_inputs;
        } else if (stop > n_inputs) {
            throw;
        } else {
            halt = stop;
        }

        uint[] memory script_lens = new uint[](halt);

        for (var i = 0; i < halt; i++) {
            pos += 36;  // skip outpoint
            (script_len, pos) = parseVarInt(txBytes, pos);
            script_lens[i] = script_len;
            pos += script_len + 4;  // skip sig_script, seq
        }

        return (script_lens, pos);
    }
    // scan the outputs and find the values and script lengths.
    // return array of values, array of script lengths and the
    // end position of the outputs.
    // takes a 'stop' argument which sets how many outputs to
    // scan through. stop=0 => scan all.
    function scanOutputs(bytes txBytes, uint pos, uint stop)
             returns (uint[], uint[], uint)
    {
        uint n_outputs;
        uint halt;
        uint script_len;

        (n_outputs, pos) = parseVarInt(txBytes, pos);

        if (stop == 0) {
            halt = n_outputs;
        } else if (stop > n_outputs) {
            throw;
        } else {
            halt = stop;
        }

        uint[] memory script_lens = new uint[](halt);
        uint[] memory output_values = new uint[](halt);

        for (var i = 0; i < halt; i++) {
            output_values[i] = getBytesLE(txBytes, pos, 64);
            pos += 8;

            (script_len, pos) = parseVarInt(txBytes, pos);
            script_lens[i] = (script_len);
            pos += script_len;
        }

        return (output_values, script_lens, pos);
    }
}
