//----------------------------------------------------------------------------
// Copyright (C) 2001 Authors
//
// This source file may be used and distributed without restriction provided
// that this copyright statement is not removed from the file and that any
// derivative work contains the original copyright notice and the associated
// disclaimer.
//
// This source file is free software; you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published
// by the Free Software Foundation; either version 2.1 of the License, or
// (at your option) any later version.
//
// This source is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with this source; if not, write to the Free Software Foundation,
// Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
//
//----------------------------------------------------------------------------
// 
// *File Name: msp_debug.v
// 
// *Module Description:
//                      MSP430 core debug utility signals
//
// *Author(s):
//              - Olivier Girard,    olgirard@gmail.com
//
//----------------------------------------------------------------------------
// $Rev$
// $LastChangedBy$
// $LastChangedDate$
//----------------------------------------------------------------------------
`ifdef OMSP_NO_INCLUDE
`else
`include "openMSP430_defines.v"
`endif

module msp_debug (

// OUTPUTs
	dma_state,					   // DMA controller state
    e_state,                       // Execution state
    i_state,                       // Instruction fetch state
    inst_cycle,                    // Cycle number within current instruction
    inst_full,                     // Currently executed instruction (full version)
    inst_number,                   // Instruction number since last system reset
    inst_pc,                       // Instruction Program counter
    inst_short,                    // Currently executed instruction (short version)

// INPUTs
    mclk,                          // Main system clock
    puc_rst                        // Main system reset
);


// OUTPUTs
//============
output	[8*32-1:0] dma_state;	   // DMA controller state 
output  [8*32-1:0] e_state;        // Execution state
output  [8*32-1:0] i_state;        // Instruction fetch state
output      [31:0] inst_cycle;     // Cycle number within current instruction
output  [8*32-1:0] inst_full;      // Currently executed instruction (full version)
output      [31:0] inst_number;    // Instruction number since last system reset
output      [15:0] inst_pc;        // Instruction Program counter
output  [8*32-1:0] inst_short;     // Currently executed instruction (short version)

// INPUTs
//============
input              mclk;           // Main system clock
input              puc_rst;        // Main system reset


//=============================================================================
// 1) ASCII FORMATING FUNCTIONS
//=============================================================================

// This function simply concatenates two strings together, ignorning the NULL
// at the end of string2.
// The specified number of space will be inserted between string1 and string2
function [64*8-1:0] myFormat;

  input [32*8-1:0] string1;
  input [32*8-1:0] string2;
  input      [3:0] space;
     
  integer i,j;      
  begin
     myFormat = 0;
`ifdef VXL			// no +:
`else
     j        = 0;
     for ( i=0; i < 32; i=i+1)                      // Copy string2
       begin
	  myFormat[8*i +: 8] = string2[8*i +: 8];
	  if ((string2[8*i +: 8] == 0) && (j == 0)) j=i;  
       end

     for ( i=0; i < space; i=i+1)                   // Add spaces
       myFormat[8*(j+i) +: 8] = " ";
     j=j+space;
     
     for ( i=0; i < 32; i=i+1)                      // Copy string1
       myFormat[8*(j+i) +: 8] = string1[8*i +: 8];
`endif     
  end
endfunction

    
//=============================================================================
// 2) CONNECTIONS TO MSP430 CORE INTERNALS
//=============================================================================

wire  [2:0] i_state_bin 		= tb_openMSP430.dut.frontend_0.i_state;
wire  [4:0] e_state_bin			= tb_openMSP430.dut.frontend_0.e_state;
wire        decode      		= tb_openMSP430.dut.frontend_0.decode;
wire [15:0] ir          		= tb_openMSP430.dut.frontend_0.ir;
wire        irq_detect  		= tb_openMSP430.dut.frontend_0.irq_detect;
wire  [3:0] irq_num     		= tb_openMSP430.dut.frontend_0.irq_num;
wire [15:0] pc          		= tb_openMSP430.dut.frontend_0.pc;


`ifdef DMA_CONTR_TEST
wire  [4:0]  dma_cntrl_state    = tb_openMSP430.dma_cntrl.state;
wire  [15:0] dev_config_reg     = tb_openMSP430.dma_dev0.config_reg;
//Instantiate the FIFO registers 
genvar gi;
	`ifdef tb_FIFO_DEPTH
		localparam depth = `tb_FIFO_DEPTH;
	`else	
		localparam depth = tb_openMSP430.dma_cntrl.FIFO_DEPTH;
	`endif 
generate for (gi=0; gi<(2**depth); gi=gi+1) begin : fifo_regs
wire [16:0] fifo_register = tb_openMSP430.dma_cntrl.fifo_mem.genregs[gi].fifo.register;
end 
endgenerate	
`endif 
//=============================================================================
// 3) GENERATE DEBUG SIGNALS
//=============================================================================

// Instruction fetch state
//=========================
reg [8*32-1:0] i_state;

always @(i_state_bin)
    case(i_state_bin)
      3'h0    : i_state =  "IRQ_FETCH";
      3'h1    : i_state =  "IRQ_DONE";
      3'h2    : i_state =  "DEC";
      3'h3    : i_state =  "EXT1";
      3'h4    : i_state =  "EXT2";
      3'h5    : i_state =  "IDLE";
      default : i_state =  "XXXXX";
    endcase
   

// Execution state
//=========================
  
reg [8*32-1:0] e_state;

always @(e_state_bin)
    case(e_state_bin)
      5'h2    : e_state =  "IRQ_0";
      5'h1    : e_state =  "IRQ_1";
      5'h0    : e_state =  "IRQ_2";
      5'h3    : e_state =  "IRQ_3";
      5'h4    : e_state =  "IRQ_4";
      5'h5    : e_state =  "SRC_AD";
      5'h6    : e_state =  "SRC_RD";
      5'h7    : e_state =  "SRC_WR";
      5'h8    : e_state =  "DST_AD";
      5'h9    : e_state =  "DST_RD";
      5'hA    : e_state =  "DST_WR";
      5'hB    : e_state =  "EXEC";
      5'hC    : e_state =  "JUMP";
      5'hD    : e_state =  "IDLE";
      5'hE    : e_state =  "SPM";
      5'hF    : e_state =  "DST_WR2";
      5'h10   : e_state =  "IRQ_PRE";
      5'h11   : e_state =  "IRQ_EXT_0";
      5'h12   : e_state =  "IRQ_EXT_1";
      5'h13   : e_state =  "IRQ_SP_RD";
      5'h14   : e_state =  "IRQ_SP_WR";
      default : e_state =  "xxxx";
    endcase


// Count instruction number & cycles
//====================================

reg [31:0]  inst_number;
always @(posedge mclk or posedge puc_rst)
  if (puc_rst)     inst_number  <= 0;
  else if (decode) inst_number  <= inst_number+1;

reg [31:0]  inst_cycle;
always @(posedge mclk or posedge puc_rst)
  if (puc_rst)     inst_cycle <= 0;
  else if (decode) inst_cycle <= 0;
  else             inst_cycle <= inst_cycle+1;


// Decode instruction
//====================================

// Buffer opcode
reg [15:0]  opcode;
always @(posedge mclk or posedge puc_rst)
  if (puc_rst)     opcode  <= 0;
  else if (decode) opcode  <= ir;

// Interrupts
reg irq;
always @(posedge mclk or posedge puc_rst)
  if (puc_rst)     irq     <= 1'b1;
  else if (decode) irq     <= irq_detect;

// Instruction type
reg [8*32-1:0] inst_type;
always @(opcode or irq)
  if (irq)
    inst_type =  "IRQ";
  else
    case(opcode[15:13])
      3'b000  : inst_type =  "SIG-OP";
      3'b001  : inst_type =  "JUMP";
      default : inst_type =  "TWO-OP";
    endcase


// Instructions name
reg [8*32-1:0] inst_name;
always @(opcode or inst_type or irq_num)
  if (inst_type=="IRQ")
    case(irq_num[3:0])
      4'b0000        : inst_name =  "IRQ 0";
      4'b0001        : inst_name =  "IRQ 1";
      4'b0010        : inst_name =  "IRQ 2";
      4'b0011        : inst_name =  "IRQ 3";
      4'b0100        : inst_name =  "IRQ 4";
      4'b0101        : inst_name =  "IRQ 5";
      4'b0110        : inst_name =  "IRQ 6";
      4'b0111        : inst_name =  "IRQ 7";
      4'b1000        : inst_name =  "IRQ 8";
      4'b1001        : inst_name =  "IRQ 9";
      4'b1010        : inst_name =  "IRQ 10";
      4'b1011        : inst_name =  "IRQ 11";
      4'b1100        : inst_name =  "IRQ 12";
      4'b1101        : inst_name =  "IRQ 13";
      4'b1110        : inst_name =  "NMI";
      default        : inst_name =  "RESET";
    endcase
  else if (inst_type=="SIG-OP")
    case(opcode[15:7])
      9'b000100_000  : inst_name =  "RRC";
      9'b000100_001  : inst_name =  "SWPB";
      9'b000100_010  : inst_name =  "RRA";
      9'b000100_011  : inst_name =  "SXT";
      9'b000100_100  : inst_name =  "PUSH";
      9'b000100_101  : inst_name =  "CALL";
      9'b000100_110  : inst_name =  "RETI";
      default        : inst_name =  "xxxx";
    endcase
  else if (inst_type=="JUMP")
    case(opcode[15:10])
      6'b001_000     : inst_name =  "JNE";
      6'b001_001     : inst_name =  "JEQ";
      6'b001_010     : inst_name =  "JNC";
      6'b001_011     : inst_name =  "JC";
      6'b001_100     : inst_name =  "JN";
      6'b001_101     : inst_name =  "JGE";
      6'b001_110     : inst_name =  "JL";
      6'b001_111     : inst_name =  "JMP";
      default        : inst_name =  "xxxx";
    endcase
  else if (inst_type=="TWO-OP")
    case(opcode[15:12])
      4'b0100        : inst_name =  "MOV";
      4'b0101        : inst_name =  "ADD";
      4'b0110        : inst_name =  "ADDC";
      4'b0111        : inst_name =  "SUBC";
      4'b1000        : inst_name =  "SUB";
      4'b1001        : inst_name =  "CMP";
      4'b1010        : inst_name =  "DADD";
      4'b1011        : inst_name =  "BIT";
      4'b1100        : inst_name =  "BIC";
      4'b1101        : inst_name =  "BIS";
      4'b1110        : inst_name =  "XOR";
      4'b1111        : inst_name =  "AND";
      default        : inst_name =  "xxxx";
    endcase

// Instructions byte/word mode
reg [8*32-1:0] inst_bw;
always @(opcode or inst_type)
  if (inst_type=="IRQ")
    inst_bw =  "";
  else if (inst_type=="SIG-OP")
    inst_bw =  opcode[6] ? ".B" : "";
  else if (inst_type=="JUMP")
    inst_bw =  "";
  else if (inst_type=="TWO-OP")
    inst_bw =  opcode[6] ? ".B" : "";

// Source register
reg [8*32-1:0] inst_src;
wire     [3:0] src_reg = (inst_type=="SIG-OP") ? opcode[3:0] : opcode[11:8];

always @(src_reg or inst_type)
  if (inst_type=="IRQ")
    inst_src =  "";
  else if (inst_type=="JUMP")
    inst_src =  "";
  else if ((inst_type=="SIG-OP") || (inst_type=="TWO-OP"))
    case(src_reg)
      4'b0000 : inst_src =  "r0";
      4'b0001 : inst_src =  "r1";
      4'b0010 : inst_src =  "r2";
      4'b0011 : inst_src =  "r3";
      4'b0100 : inst_src =  "r4";
      4'b0101 : inst_src =  "r5";
      4'b0110 : inst_src =  "r6";
      4'b0111 : inst_src =  "r7";
      4'b1000 : inst_src =  "r8";
      4'b1001 : inst_src =  "r9";
      4'b1010 : inst_src =  "r10";
      4'b1011 : inst_src =  "r11";
      4'b1100 : inst_src =  "r12";
      4'b1101 : inst_src =  "r13";
      4'b1110 : inst_src =  "r14";
      default : inst_src =  "r15";
    endcase

// Destination register
reg [8*32-1:0] inst_dst;
always @(opcode or inst_type)
  if (inst_type=="IRQ")
    inst_dst =  "";
  else if (inst_type=="SIG-OP")
    inst_dst =  "";
  else if (inst_type=="JUMP")
    inst_dst =  "";
  else if (inst_type=="TWO-OP")
    case(opcode[3:0])
      4'b0000 : inst_dst =  "r0";
      4'b0001 : inst_dst =  "r1";
      4'b0010 : inst_dst =  "r2";
      4'b0011 : inst_dst =  "r3";
      4'b0100 : inst_dst =  "r4";
      4'b0101 : inst_dst =  "r5";
      4'b0110 : inst_dst =  "r6";
      4'b0111 : inst_dst =  "r7";
      4'b1000 : inst_dst =  "r8";
      4'b1001 : inst_dst =  "r9";
      4'b1010 : inst_dst =  "r10";
      4'b1011 : inst_dst =  "r11";
      4'b1100 : inst_dst =  "r12";
      4'b1101 : inst_dst =  "r13";
      4'b1110 : inst_dst =  "r14";
      default : inst_dst =  "r15";
    endcase

// Source Addressing mode
reg [8*32-1:0] inst_as;
always @(inst_type or src_reg or opcode or inst_src)
  begin
  if (inst_type=="IRQ")
    inst_as =  "";
  else if (inst_type=="JUMP")
    inst_as =  "";
  else if (src_reg==4'h3) // Addressing mode using R3
    case (opcode[5:4])
      2'b11  : inst_as =  "#-1";
      2'b10  : inst_as =  "#2";
      2'b01  : inst_as =  "#1";
      default: inst_as =  "#0";
    endcase
  else if (src_reg==4'h2) // Addressing mode using R2
    case (opcode[5:4])
      2'b11  : inst_as =  "#8";
      2'b10  : inst_as =  "#4";
      2'b01  : inst_as =  "&EDE";
      default: inst_as =  inst_src;
    endcase
  else if (src_reg==4'h0) // Addressing mode using R0
    case (opcode[5:4])
      2'b11  : inst_as =  "#N";
      2'b10  : inst_as =  myFormat("@", inst_src, 0);
      2'b01  : inst_as =  "EDE";
      default: inst_as =  inst_src;
    endcase
  else                    // General Addressing mode
    case (opcode[5:4])
      2'b11  : begin
	       inst_as =  myFormat("@", inst_src, 0);
	       inst_as =  myFormat(inst_as, "+", 0);
               end
      2'b10  : inst_as =  myFormat("@", inst_src, 0);
      2'b01  : begin
	       inst_as =  myFormat("x(", inst_src, 0);
  	       inst_as =  myFormat(inst_as, ")", 0);
               end
      default: inst_as =  inst_src;
    endcase
  end

// Destination Addressing mode
reg [8*32-1:0] inst_ad;
always @(opcode or inst_type or inst_dst)
  begin
     if (inst_type!="TWO-OP")
       inst_ad =  "";
     else if (opcode[3:0]==4'h2)   // Addressing mode using R2
       case (opcode[7])
	 1'b1   : inst_ad =  "&EDE";
	 default: inst_ad =  inst_dst;
       endcase
     else if (opcode[3:0]==4'h0)   // Addressing mode using R0
       case (opcode[7])
	 2'b1   : inst_ad =  "EDE";
	 default: inst_ad =  inst_dst;
       endcase
     else                          // General Addressing mode
       case (opcode[7])
	 2'b1   : begin
	          inst_ad =  myFormat("x(", inst_dst, 0);
  	          inst_ad =  myFormat(inst_ad, ")", 0);
                  end
	 default: inst_ad =  inst_dst;
       endcase
  end


// Currently executed instruction
//================================

wire [8*32-1:0] inst_short = inst_name;

reg  [8*32-1:0] inst_full;
always @(inst_type or inst_name or inst_bw or inst_as or inst_ad)
  begin
     inst_full   = myFormat(inst_name, inst_bw, 0);
     inst_full   = myFormat(inst_full, inst_as, 1);
     if (inst_type=="TWO-OP")
       inst_full = myFormat(inst_full, ",",     0);
     inst_full   = myFormat(inst_full, inst_ad, 1);
     if (opcode==16'h4303)
       inst_full = "NOP";
     if (opcode==`DBG_SWBRK_OP)
       inst_full = "SBREAK";
     if (opcode==16'h1380)
       inst_full = "SM_DISABLE";
     if (opcode==16'h1381)
       inst_full = "SM_ENABLE";
     if (opcode==16'h1382)
       inst_full = "SM_VERIFY_ADDR";
     if (opcode==16'h1383)
       inst_full = "SM_VERIFY_PREV";
     if (opcode==16'h1384)
       inst_full = "SM_AE_WRAP";
     if (opcode==16'h1385)
       inst_full = "SM_AE_UNWRAP";
     if (opcode==16'h1386)
       inst_full = "SM_ID";
     if (opcode==16'h1387)
       inst_full = "SM_CALLER_ID";
     if (opcode==16'h1388)
       inst_full = "SM_STACK_GUARD";
  end
   

// Instruction program counter
//================================

reg  [15:0] inst_pc;
always @(posedge mclk or posedge puc_rst)
  if (puc_rst)     inst_pc  <=  16'h0000;
  else if (decode) inst_pc  <=  pc;
  
// DMA controller states (sergio)
//===============================

/*reg [15*8:0] dma_dev_state; //states stored in ASCII 

always @(dma_device_state)
    case(dma_device_state)
      	0	 : dma_dev_state   = "RESET";
		1	 : dma_dev_state   = "IDLE";
		2	 : dma_dev_state   = "GET_ADDRESS";
		3	 : dma_dev_state   = "GENERATE_RQST";
		4	 : dma_dev_state   = "WAIT_RD_DATA";
		5	 : dma_dev_state   = "GET_RD_DATA";
		7	 : dma_dev_state   = "ERROR_RD";
		6	 : dma_dev_state   = "END_READ";
		8	 : dma_dev_state   = "WAIT_RQ_RD";
		9	 : dma_dev_state   = "WAIT_RD";
		10	 : dma_dev_state   = "TB_WAIT_WR";
		11	 : dma_dev_state   = "START_SENDING";
		12	 : dma_dev_state   = "SEND_DATA";
		16	 : dma_dev_state   = "END_WRITE";
		15	 : dma_dev_state   = "DATA_WRITTEN";
		13	 : dma_dev_state   = "WAIT_RQ_WR";
		14	 : dma_dev_state   = "WAIT_WR";
		17	 : dma_dev_state   = "DMA_WRITING_MEM";
		18	 : dma_dev_state   = "START_RECEIVING";
     default : dma_dev_state  = "XXXXX";
    endcase*/

`ifdef DMA_CONTR_TEST

reg [8*32-1:0] dma_state;  
   
always @(dma_cntrl_state)
	case(dma_cntrl_state)
		0	: dma_state   = "IDLE";
		1	: dma_state   = "GET_REGS";
		2	: dma_state   = "LOAD_DMA_ADD";
		3	: dma_state   = "READ_MEM";
		4	: dma_state   = "ERROR";
		5	: dma_state   = "OLD_ADDR_RD";
		6	: dma_state   = "SEND_TO_DEV0";
		7	: dma_state   = "WAIT_READ";
		8	: dma_state   = "SEND_TO_DEV1";
		9	: dma_state   = "NOP";
		10	: dma_state   = "END_READ";
		11	: dma_state   = "READ_DEV0";
		12	: dma_state   = "READ_DEV1";
		13	: dma_state   = "WAIT_WRITE";	
		14	: dma_state   = "SEND_TO_MEM0";
		15	: dma_state   = "SEND_TO_MEM1";		
		16	: dma_state   = "OLD_ADDR_WR";
		17	: dma_state   = "END_WRITE";
		26  : dma_state   = "FIFO_FULL_RD";
		18	: dma_state   = "WAIT_DEV";
		19	: dma_state   = "EMPTY_FIFO_READ";
		25  : dma_state   = "RESTORE_MSP_COUNT";
		20	: dma_state   = "RESET";      	
		21  : dma_state   = "FIFO_FULL_WR";
		22  : dma_state   = "EMPTY_FIFO_WRITE";
		23  : dma_state   = "OLD_ADDR_EMP_FIFO_W";	
		24  : dma_state   = "RESTORE_DEV_COUNT";
	default : dma_state   = "XXXXX";
	endcase
	
reg [8*32-1:0] config_reg;  
   
always @(dev_config_reg)
	case(dev_config_reg)
		16'h0003 : config_reg = "MMIO_READ";
		16'h0001 : config_reg = "MMIO_WRITE";
		16'h0005 : config_reg = "READ_OP";          
		16'h8004 : config_reg = "END_READ";
		16'h0009 : config_reg = "WRITE_OP";
		16'h0809 : config_reg = "WRITE_OK";       
		16'h001D : config_reg = "READ_OP_ACK";
		16'h200D : config_reg = "WAIT_READ_ACK";  
		16'hA00C : config_reg = "END_READ_ACK"; 
		16'h0020 : config_reg = "RESET_REGS";	
		16'h0200 : config_reg = "DMA_ERROR";	
		default  : config_reg = "XXXXX";
endcase
`endif

// Registers
//===============================
wire [15:0]	r1	= tb_openMSP430.dut.execution_unit_0.register_file_0.r1[15:0];
wire [15:0]	r2	= tb_openMSP430.dut.execution_unit_0.register_file_0.r2[15:0];
wire [15:0]	r3	= tb_openMSP430.dut.execution_unit_0.register_file_0.r3[15:0];
wire [15:0]	r4	= tb_openMSP430.dut.execution_unit_0.register_file_0.r4[15:0];
wire [15:0]	r5	= tb_openMSP430.dut.execution_unit_0.register_file_0.r5[15:0];
wire [15:0]	r6	= tb_openMSP430.dut.execution_unit_0.register_file_0.r6[15:0];
wire [15:0]	r7	= tb_openMSP430.dut.execution_unit_0.register_file_0.r7[15:0];
wire [15:0]	r8	= tb_openMSP430.dut.execution_unit_0.register_file_0.r8[15:0];
wire [15:0]	r9	= tb_openMSP430.dut.execution_unit_0.register_file_0.r9[15:0];
wire [15:0]	r10	= tb_openMSP430.dut.execution_unit_0.register_file_0.r10[15:0];
wire [15:0]	r11	= tb_openMSP430.dut.execution_unit_0.register_file_0.r11[15:0];
wire [15:0]	r12	= tb_openMSP430.dut.execution_unit_0.register_file_0.r12[15:0];
wire [15:0]	r13	= tb_openMSP430.dut.execution_unit_0.register_file_0.r13[15:0];
wire [15:0]	r14	= tb_openMSP430.dut.execution_unit_0.register_file_0.r14[15:0];
wire [15:0]	r15	= tb_openMSP430.dut.execution_unit_0.register_file_0.r15[15:0];

endmodule // msp_debug

