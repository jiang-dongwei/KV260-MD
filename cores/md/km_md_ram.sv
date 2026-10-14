// SPDX-License-Identifier: GPL-3.0-or-later
// Interfaces of the pinned Genesis bram.vhd, implemented with inferred AMD RAM.
// Input enables gate address/data capture; cs gates writes and masks outputs.
// Same-port read during write is write-first. Cross-port collisions remain
// undefined, as in the original Intel memory. No reset on memory arrays.
module spram_sz #(parameter addr_width=8,data_width=8,numwords=256,
    mem_init_file=" ",mem_name="MEM")(
    input wire clock,input wire [addr_width-1:0] address,
    input tri0 [data_width-1:0] data,input tri1 enable,input tri0 wren,
    output wire [data_width-1:0] q,input tri1 cs
);
    (* ram_style="block" *) reg [data_width-1:0] memory [0:numwords-1];
    reg [data_width-1:0] read_data;
    initial begin
        for(integer i=0;i<numwords;i=i+1) memory[i]=0;
        if(mem_init_file!=" " && mem_init_file!="") $readmemh(mem_init_file,memory);
    end
    // The upstream spram deliberately bypasses enable.
    always @(posedge clock) begin
        if(wren && cs) begin memory[address]<=data;read_data<=data;end
        else read_data<=memory[address];
    end
    assign q=cs ? read_data : {data_width{1'b1}};
endmodule

module spram #(parameter addr_width=8,data_width=8,mem_init_file=" ",mem_name="MEM")(
    input wire clock,input wire [addr_width-1:0] address,
    input tri0 [data_width-1:0] data,input tri1 enable,input tri0 wren,
    output wire [data_width-1:0] q,input tri1 cs
);
    spram_sz #(addr_width,data_width,1<<addr_width,mem_init_file,mem_name) ram(.*);
endmodule

module km_md_ram_bank #(parameter ADDR_BITS=8,WIDTH=8)(
    input wire clock,clock_b,input wire [ADDR_BITS-1:0] address_a,address_b,
    input wire [WIDTH-1:0] data_a,data_b,input wire enable_a,enable_b,wren_a,wren_b,
    output reg [WIDTH-1:0] q_a,q_b
);
    (* ram_style="block" *) reg [WIDTH-1:0] memory [0:(1<<ADDR_BITS)-1];
    initial for(integer i=0;i<(1<<ADDR_BITS);i=i+1) memory[i]=0;
    always @(posedge clock) if(enable_a) begin
        if(wren_a) begin memory[address_a]<=data_a;q_a<=data_a;end
        else q_a<=memory[address_a];
    end
    always @(posedge clock_b) if(enable_b) begin
        if(wren_b) begin memory[address_b]<=data_b;q_b<=data_b;end
        else q_b<=memory[address_b];
    end
endmodule

// Direct asymmetric callers bind the original VHDL defaults explicitly.
// Keep internal ports ordinary wires: nested weak pull defaults can mask
// a connected write-enable in elaboration tools. The dpram wrapper retains
// the public single-width defaults.
module dpram_dif #(parameter addr_width_a=8,data_width_a=8,
    addr_width_b=8,data_width_b=8,mem_init_file=" ",SEPARATE_CLOCK_B=0)(
    input wire clock,input wire clock_b,input wire [addr_width_a-1:0] address_a,
    input wire [data_width_a-1:0] data_a,input wire enable_a,input wire wren_a,
    output wire [data_width_a-1:0] q_a,input wire cs_a,
    input wire [addr_width_b-1:0] address_b,
    input wire [data_width_b-1:0] data_b,input wire enable_b,input wire wren_b,
    output wire [data_width_b-1:0] q_b,input wire cs_b
);
    initial begin
        if(mem_init_file!=" " && mem_init_file!="") $fatal(1,"MD dpram initialization file unsupported");
        if(!((data_width_b==data_width_a && addr_width_b==addr_width_a) ||
             (data_width_b==2*data_width_a && addr_width_a==addr_width_b+1)))
            $fatal(1,"Unexpected MD asymmetric RAM geometry");
    end
    wire [data_width_a-1:0] qa;
    wire [data_width_b-1:0] qb;
    if(data_width_a==data_width_b) begin: equal_width
        km_md_ram_bank #(addr_width_a,data_width_a) bank(
            .clock(clock),.clock_b(SEPARATE_CLOCK_B ? clock_b : clock),.address_a(address_a),.address_b(address_b),
            .data_a(data_a),.data_b(data_b),.enable_a(enable_a),.enable_b(enable_b),
            .wren_a(wren_a && cs_a),.wren_b(wren_b && cs_b),.q_a(qa),.q_b(qb));
    end else begin: double_width
        wire [data_width_a-1:0] lane_q[0:1];
        reg lane;
        always @(posedge clock) if(enable_a) lane<=address_a[0];
        km_md_ram_bank #(addr_width_b,data_width_a) bank0(
            .clock(clock),.clock_b(SEPARATE_CLOCK_B ? clock_b : clock),
            .address_a(address_a[addr_width_a-1:1]),.address_b(address_b),
            .data_a(data_a),.data_b(data_b[0*data_width_a+:data_width_a]),
            .enable_a(enable_a),.enable_b(enable_b),
            .wren_a(wren_a && cs_a && address_a[0]==1'b0),.wren_b(wren_b && cs_b),
            .q_a(lane_q[0]),.q_b(qb[0*data_width_a+:data_width_a]));
        km_md_ram_bank #(addr_width_b,data_width_a) bank1(
            .clock(clock),.clock_b(SEPARATE_CLOCK_B ? clock_b : clock),
            .address_a(address_a[addr_width_a-1:1]),.address_b(address_b),
            .data_a(data_a),.data_b(data_b[1*data_width_a+:data_width_a]),
            .enable_a(enable_a),.enable_b(enable_b),
            .wren_a(wren_a && cs_a && address_a[0]==1'b1),.wren_b(wren_b && cs_b),
            .q_a(lane_q[1]),.q_b(qb[1*data_width_a+:data_width_a]));
        assign qa=lane_q[lane];
    end
    assign q_a=cs_a ? qa : {data_width_a{1'b1}};
    assign q_b=cs_b ? qb : {data_width_b{1'b1}};
endmodule

module dpram #(parameter addr_width=8,data_width=8,mem_init_file=" ")(
    input wire clock,input wire [addr_width-1:0] address_a,
    input tri0 [data_width-1:0] data_a,input tri1 enable_a,input tri0 wren_a,
    output wire [data_width-1:0] q_a,input tri1 cs_a,
    input tri0 [addr_width-1:0] address_b,
    input tri0 [data_width-1:0] data_b,input tri1 enable_b,input tri0 wren_b,
    output wire [data_width-1:0] q_b,input tri1 cs_b
);
    dpram_dif #(addr_width,data_width,addr_width,data_width,mem_init_file) ram(.clock_b(1'b0),.*);
endmodule

module mlab #(parameter addr_width=8,data_width=8)(
    input wire clock,input wire [addr_width-1:0] rdaddress,wraddress,
    input tri0 [data_width-1:0] data,input tri0 wren,
    output wire [data_width-1:0] q,input tri1 cs
);
    (* ram_style="distributed" *) reg [data_width-1:0] memory[0:(1<<addr_width)-1];
    initial for(integer i=0;i<(1<<addr_width);i=i+1) memory[i]=0;
    always @(posedge clock) if(wren) memory[wraddress]<=data;
    assign q=cs ? memory[rdaddress] : {data_width{1'b1}};
endmodule
