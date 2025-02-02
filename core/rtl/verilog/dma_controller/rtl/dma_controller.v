module dma_controller ( 
	clk,
	reset,
	// Inputs from Device
	num_words,
	start_addr,
	mmio_input_addr,
	rd_wr,
	rqst,
	dev_ack,
	dev_in,
	// Outputs to Device
	dma_ack,
	dev_out,
	end_flag,
	error_flag,
	
	// Inputs from OpenMSP430
	dma_in,
	dma_ready, 
	dma_resp,
	// Outputs to OpenMSP430
	dma_addr,
	dma_out,
	dma_en,
	dma_priority,
	dma_we
);

`ifdef SIM
 initial begin
  $display("DMA: Simulation acquired at %2d",$time);
 end
`endif

parameter ADD_LEN = 16; // Number of bits for the addresses
parameter DATA_LEN = 16; // Number of bits for the data
// 2^FIFO_DEPTH = regs in the FIFO.
parameter FIFO_DEPTH = $clog2(`DMEM_SIZE>>9); // The default choice for the FIFO depth is to have it = DMEM_SIZE / 512,  so that when a 16-kB the data memory is used, the controller internal buffer would be of 32 bytes
parameter FIFO_DIV_FACTOR = (FIFO_DEPTH > 8) ? 3 : 2; // by default divide by 8. Se ho solo 8 registri, dividi per 2.

input clk, reset;

//-------Device interface ------//
input [ADD_LEN-1:0] num_words;  // 1) I should be able to write at max. as many words as the fifo can handle (=2^FIFO_DEPTH words),
								// which you write onto FIFO_DEPTH bits.
								// 2) Or num_words can bigger and let FIFO_FULL FSM-branch handle the situation.It's up to you. +++
								
input [ADD_LEN:0]   start_addr;
wire  [ADD_LEN-1:0] start_addr_shifted = start_addr >> 1; // In the memory backbone dma_addr[15:1], so it's considered as multiplied by 2. To be consistent, now I divide it
input [ADD_LEN:0]   mmio_input_addr; //starting address for mmio operations
wire  [ADD_LEN-1:0] mmio_add_shifted = mmio_input_addr >> 1; // In the memory backbone dma_addr[15:1], so it's considered as multiplied by 2. To be consistent, now I divide it

input rd_wr;
input rqst;
input dev_ack;
input [DATA_LEN-1:0] dev_in;
output [DATA_LEN-1:0] dev_out;
output reg dma_ack;
output reg end_flag;

//-------OpenMSP430 interface----//
input [DATA_LEN-1:0] dma_in;
input dma_ready;
input dma_resp;
output [ADD_LEN-1:0] dma_addr;
output [DATA_LEN-1:0] dma_out;
output reg dma_en;
output reg dma_priority; 
output reg [1:0] dma_we;
output reg error_flag;

//--------------------------------//
//--------------------------------//
//  Internal variables and wires  //
//--------------------------------//
//--------------------------------//

// Fifo
//-----------------------------
wire fifo_full, fifo_empty, fifo_empty_partial;
wire [DATA_LEN-1:0] fifo_out, fifo_in;
reg fifo_rst, fifo_old_add_flag;
reg fifo_en, fifo_wr_rd;
// Address register 
//-----------------------------
wire [ADD_LEN-1:0] start_address;
wire [ADD_LEN-1:0] address;
reg  addr0_rst, addr0_reg_en;

// MMIO address register 
//-----------------------------
wire [ADD_LEN-1:0] mmio_address;
reg  mmio_add_rst, mmio_add_en, mmio_ff_en, mmio_ff_rst;
wire mmio_flag, mmio_mux_reg;

// Old Address register
//-----------------------------
wire [ADD_LEN-1:0] old_address;
reg  old_addr_reg_en, old_addr_rst;
// Flip-flop Mux Add
//-----------------------------
reg mux_old_addr;
// Num_words register
//-----------------------------
wire [ADD_LEN-1:0] words;
reg words_rst, words_reg_en;
// Counter
//-----------------------------
wire end_count;
wire [ADD_LEN-2:0] count;	
wire [ADD_LEN-2:0] dev_count_saved;
wire [ADD_LEN-2:0] msp_count_saved;
wire [ADD_LEN-2:0] saved_value;
wire [FIFO_DEPTH-1:0] count_in;	
wire dev_count_reg_en;
reg count_rst, count_en, load_dev_or_msp, count_load;
reg msp_count_reg_en_f, dev_count_reg_en_f; //flags to enable counter saving when handling FIFO FULL  
reg dev_count_rst, msp_count_rst;
// FSM control logic  
//-----------------------------
wire num_words_null;
reg flag_cnt_words, flag_cnt_words_mem; //end-counts for the FSM
reg out_to_msp; //1: FIFO out to DMA || 0: FIFO out to DEV
reg drive_dma_addr; //0: dma_addr = 'hz || 1: dma_addr

// FSM States Definition
reg [4:0]state, next_state; //just codifies the states

localparam 	IDLE                = 0,
			GET_REGS            = 1,
			// Read
			LOAD_DMA_ADD        = 2,
			READ_MEM            = 3,
			ERROR               = 4,
			OLD_ADDR_RD         = 5,
			SEND_TO_DEV0        = 6,
			WAIT_READ           = 7,
			SEND_TO_DEV1        = 8,
			NOP                 = 9,
			END_READ            = 10,
			//Write
			READ_DEV0           = 11,
			READ_DEV1           = 12,
			WAIT_WRITE          = 13,
			SEND_TO_MEM0        = 14,
			SEND_TO_MEM1        = 15,
			OLD_ADDR_WR         = 16,
			END_WRITE           = 17,
			// Fifo full
			FIFO_FULL_RD        = 26,
			WAIT_DEV            = 18,
			EMPTY_FIFO_READ     = 19,
			RESTORE_MSP_COUNT   = 25,
			//
			FIFO_FULL_WR        = 21,
			EMPTY_FIFO_WRITE    = 22,
			OLD_ADDR_EMP_FIFO_W = 23,
			RESTORE_DEV_COUNT   = 24,
			RESET               = 20;	

//--------------------------------//
//--------------------------------//
//  		Datapath			  //
//--------------------------------//
//--------------------------------//

// Mux fifo in's and out's
assign dma_out = out_to_msp ? fifo_out : {DATA_LEN{1'bz}};
assign dev_out = out_to_msp ? {DATA_LEN{1'bz}} : fifo_out;
assign fifo_in = out_to_msp ? dev_in : dma_in;
// Check NUM_WORDS and ADDRESS validity 
assign num_words_null = ~|num_words; //if words = 0x0000 then do not even start the count, it will access forever the memory 

fifo #(	.DATA(DATA_LEN), 
		.ADDR_SIZE(FIFO_DEPTH),
		.DIV_FACTOR(FIFO_DIV_FACTOR)) fifo_mem (
		.clk(clk), 
		.fifo_enable(fifo_en),
		.fifo_wr_rd(fifo_wr_rd),
		.rst(fifo_rst),
		.full(fifo_full),
		.empty(fifo_empty),
		.empty_partial(fifo_empty_partial),
		.fifo_in(fifo_in), 
		.fifo_out(fifo_out),
		.fifo_old_add_flag(fifo_old_add_flag));

// DMA's internal registers
register #(.REG_DEPTH(ADD_LEN)) word0 (
				.clk(clk),
				.reg_en(words_reg_en),
				.data_in(num_words),
				.rst(words_rst),
				.data_out(words));

register #(.REG_DEPTH(ADD_LEN)) addr0 (
				.clk(clk),
				.reg_en(addr0_reg_en),
				.data_in(start_addr_shifted),
				.rst(addr0_rst),
				.data_out(start_address));
				
register #(.REG_DEPTH(ADD_LEN)) old_addr0 (
				.clk(clk),
				.reg_en(old_addr_reg_en & ~msp_count_reg_en),
				.data_in(address),
				.rst(old_addr_rst),
				.data_out(old_address));

register #(.REG_DEPTH(ADD_LEN)) mmio_addr0 (
				.clk(clk),
				.reg_en(mmio_add_en),
				.data_in(mmio_add_shifted),
				.rst(mmio_add_rst),
				.data_out(mmio_address));
				
register #(1) ff_mmio_mux (
				.clk(clk),
				.reg_en(mmio_ff_en),
				.data_in(mmio_flag),
				.rst(mmio_ff_rst),
				.data_out(mmio_mux_reg));

assign mmio_flag = mmio_input_addr != {ADD_LEN{1'b0}}; // if mmio_addr != 0, then a MMIO has been set!		
// Notice tht doing this is licit as the mmio_input_addr comes from a register of the DMA controller drvier, thus is a stable input.

wire [ADD_LEN-1:0] muxed_address = mmio_mux_reg ? mmio_address : start_address;						
		
assign address = muxed_address + count;
assign dma_addr = drive_dma_addr ? ( mux_old_addr ? old_address : address) :
					{ADD_LEN{1'bz}};// {1'b0}}; XXX: puoi mettere 1'b0 per questioni estetiche, 
					                // meno rosso a schermo. Funziona in entrambi i modi, però 
					                // personalmente penso sia meglio avere un indirizzo in alta  
					                // impedenza che a zero, in modo tale da accorgersi nel  
					                // caso si vada a leggerlo involontariamente.

// Counter
counter #(.L(ADD_LEN-1)) count0 (
	.clk(clk),
	.load(count_load),
	.rst(count_rst),
	.cnt_en(count_en),
	.data_in(saved_value),//{{ADD_LEN-2{1'b0}},1'b0}),
	.cnt(count),
	.end_cnt(end_count));

register #(.REG_DEPTH(ADD_LEN-1)) dev_count_reg (
	.clk(clk),
	.reg_en(dev_count_reg_en),
	.data_in(count),
	.rst(dev_count_rst),
	.data_out(dev_count_saved));

register #(.REG_DEPTH(ADD_LEN-1)) msp_count_reg (
	.clk(clk),
	.reg_en(msp_count_reg_en),
	.data_in(count),
	.rst(msp_count_rst),
	.data_out(msp_count_saved));
	
	
//assign dev_count_reg_en = (state == READ_DEV1) & fifo_full | dev_count_reg_en_f;
assign dev_count_reg_en = (state == WAIT_WRITE) & fifo_full | dev_count_reg_en_f;
assign msp_count_reg_en = (state == READ_MEM)   & fifo_full | msp_count_reg_en_f;
assign saved_value      = load_dev_or_msp ? dev_count_saved : msp_count_saved;



always @(count,words) begin
	flag_cnt_words = (count >= words-1); 
	flag_cnt_words_mem = (count == words); // flag count for the read case
end	

// State Assignment
always @(posedge clk,posedge reset)	begin
	if (reset) begin
		state <= RESET; //Asynchronus reset	
		//next_state <= RESET; synthesis error: it causes multiple driver for next_state, since the change in state <= RESET triggers the next state generation, that derives next_state
	end	else state <= next_state;
end

// Next State Generation
always @(state, rqst, rd_wr, dma_ready, fifo_full, dma_resp, flag_cnt_words, flag_cnt_words_mem, dev_ack, fifo_empty_partial, reset) begin
		next_state <= IDLE; // default
		case (state)
			RESET :
				next_state <= reset ? RESET : IDLE;
			IDLE : 		
				next_state <= rqst ? GET_REGS : IDLE;
			GET_REGS : 
				next_state <= num_words_null ? (rd_wr ? END_READ : END_WRITE) : 
				              mmio_flag ? LOAD_DMA_ADD : (rd_wr ? LOAD_DMA_ADD : READ_DEV0);
			// =============
			//     Read
			// ============= 
			LOAD_DMA_ADD :
				next_state <= dma_ready ? READ_MEM : LOAD_DMA_ADD;
			READ_MEM :
				next_state <= dma_resp  ? ERROR : 
                              fifo_full ? (mmio_flag ? FIFO_FULL_WR : FIFO_FULL_RD ) :
                              flag_cnt_words_mem ? (mmio_flag ? SEND_TO_MEM0 : SEND_TO_DEV0) :
                              dma_ready ? READ_MEM : OLD_ADDR_RD;
			OLD_ADDR_RD : 
				next_state <= dma_ready ? READ_MEM : OLD_ADDR_RD;
			ERROR :
				next_state <= END_READ; //FIXME check!	
			SEND_TO_DEV0 :
				next_state <= dev_ack ? SEND_TO_DEV1 : WAIT_READ;
			WAIT_READ :
				next_state <= dev_ack ? SEND_TO_DEV1 : WAIT_READ;				
			SEND_TO_DEV1 :
				next_state <= flag_cnt_words ? END_READ : 
				              dev_ack ? SEND_TO_DEV1 : NOP;
			NOP :
				next_state <= dev_ack ? SEND_TO_DEV1 : NOP;
			END_READ :
				next_state <= IDLE;
			// Fifo full during Read-op
			FIFO_FULL_RD: 
				next_state <= WAIT_DEV;
			WAIT_DEV : 
				next_state <= dev_ack ? EMPTY_FIFO_READ : WAIT_DEV;
			EMPTY_FIFO_READ :
			    next_state <= fifo_empty_partial ? RESTORE_MSP_COUNT : 
						      dev_ack ? EMPTY_FIFO_READ : WAIT_DEV;
			RESTORE_MSP_COUNT : 
				next_state <= flag_cnt_words_mem ? SEND_TO_DEV0 :
							  dma_ready ? READ_MEM : OLD_ADDR_RD;
			// =============
			//    Write
			// =============
			READ_DEV0 :
				next_state <= dev_ack ? READ_DEV1 : READ_DEV0;
			READ_DEV1 :
				next_state <= flag_cnt_words ? SEND_TO_MEM0 : 
							  dev_ack ? (fifo_full ? FIFO_FULL_WR : READ_DEV1) : WAIT_WRITE;
			WAIT_WRITE :
				next_state <= dev_ack ? (fifo_full ? FIFO_FULL_WR : READ_DEV1) : WAIT_WRITE;
			SEND_TO_MEM0 :
				next_state <= SEND_TO_MEM1;
			SEND_TO_MEM1 :
				next_state <= dma_resp ? ERROR : 
							  //flag_cnt_words ? END_WRITE :
							  //dma_ready ? SEND_TO_MEM1 : OLD_ADDR_WR;
							  dma_ready ? (flag_cnt_words ? END_WRITE : SEND_TO_MEM1) : OLD_ADDR_WR;	
			OLD_ADDR_WR :
				next_state <= dma_ready ? (flag_cnt_words_mem ? END_WRITE : SEND_TO_MEM1) : OLD_ADDR_WR;
			END_WRITE : 
				next_state <= IDLE;
			//Fifo_full during Write-op						      
			FIFO_FULL_WR :
				next_state <= EMPTY_FIFO_WRITE;
			EMPTY_FIFO_WRITE :
				next_state <= dma_resp ? ERROR : 
							  dma_ready ? ( fifo_empty_partial ? (mmio_flag ? RESTORE_MSP_COUNT : RESTORE_DEV_COUNT) : EMPTY_FIFO_WRITE ) : OLD_ADDR_EMP_FIFO_W;
			OLD_ADDR_EMP_FIFO_W :
				next_state <= dma_ready ? ( fifo_empty_partial ? (mmio_flag ? RESTORE_MSP_COUNT : RESTORE_DEV_COUNT) : EMPTY_FIFO_WRITE ) : OLD_ADDR_EMP_FIFO_W;
			RESTORE_DEV_COUNT : 
				next_state <= READ_DEV1;
						      
		endcase
end

// Control Signals Generation
always @(state,dma_ready) begin
	// default
	addr0_reg_en <= 1'b0;
	addr0_rst <= 1'b0;	
	count_en <= 1'b0;
	count_load <= 1'b0;
	count_rst <= 1'b0;
	dev_count_reg_en_f <= 1'b0;
	dev_count_rst <= 1'b0;
	dma_ack <= 1'b0;
	dma_en <= 1'b0;
	dma_priority <= 1'b0;
	dma_we  <= 2'b00;
	drive_dma_addr <= 1'b0;
	end_flag <= 1'b0;
	error_flag <= 1'b0;
	fifo_en <= 1'b0;
	fifo_old_add_flag <= 1'b0;
	fifo_rst <= 1'b0;
	fifo_wr_rd <= 1'b0;
	load_dev_or_msp <= 1'b0;
	mmio_add_en <= 1'b0;
	mmio_add_rst <= 1'b0;
	mmio_ff_en <= 1'b0;
	mmio_ff_rst <= 1'b0;
	msp_count_reg_en_f <= 1'b0;
	msp_count_rst <= 1'b0;
	mux_old_addr <= 1'b0;
	old_addr_reg_en <= 1'b0;
	old_addr_rst <= 1'b0;
	out_to_msp <= 1'b0;
	words_reg_en <= 1'b0;
	words_rst <= 1'b0;
	
	case (state)		
		RESET : 
		begin
			addr0_rst <= 1'b1;
			count_rst <= 1'b1;
			dev_count_rst <= 1'b1;
			fifo_rst <= 1'b1;
            mmio_add_rst <= 1'b1;
			mmio_ff_rst <= 1'b1;
			msp_count_rst <= 1'b1;
			old_addr_rst <= 1'b1;
			words_rst <= 1'b1;
		end
		IDLE : 
		begin
			addr0_rst <= 1'b1;
			count_rst <= 1'b1;	
			dev_count_rst <= 1'b1;
			fifo_rst <= 1'b1;//XXX controlla: secondo me in IDLE ci sta svuotare la FIFO e resettare i WR_ADDR e RD_ADDR, no?
			msp_count_rst <= 1'b1;
			words_rst <= 1'b1;
		end
		GET_REGS : 
		begin
			addr0_reg_en <= 1'b1;
			words_reg_en <= 1'b1;
            mmio_add_en <= 1'b1;
			`ifdef SIM 
			dma_ack <= 1'b1; // signal "rqst aquired" to DEV
			`endif
		end
		
		// =============
		//     Read
		// =============
		LOAD_DMA_ADD :  
		begin
			count_en <= 1'b1 & dma_ready;
			dma_en <= 1'b1; // needed to generate dma_ready (#171 in memory_backbone)
			drive_dma_addr <= 1'b1;
			fifo_wr_rd <= 1'b1;
		end
		READ_MEM : 
		begin
			count_en <= 1'b1;
			dma_en <= 1'b1;
			drive_dma_addr <= 1'b1;
			fifo_en <= 1'b1;
			fifo_wr_rd <= 1'b1;
			old_addr_reg_en <= 1'b1;
		end
		OLD_ADDR_RD:
		begin			
			dma_en <= 1'b1;
			drive_dma_addr <= 1'b1;
			fifo_old_add_flag <= 1'b1;
			fifo_wr_rd <= 1'b1;
			mux_old_addr <= 1'b1;
		end
		ERROR :
		begin
			drive_dma_addr <= 1'b1;
			error_flag <= 1'b1;	
			fifo_rst  <= 1'b1;
		end
		SEND_TO_DEV0 : 
		begin
			count_en <= 1'b1; //enable to allow the loading
			count_load <= 1'b1;
			load_dev_or_msp <= 1'b1;
			`ifdef SIM 
			dma_ack <= 1'b1; // to signal to DEV that the rqst has been aquired
			`endif
		end
		WAIT_READ :
		begin
			// NOP: it's not important to signal the DMA request, since the DMA is the master! 
			// Every time dev_ack goes LOW, device will say when it's ready again, then it will 
			// re-synch again passing by its synchronization 'START_READING' state. 
			// Furthermore, dma_ack will be used as "data_valid" flag and now the avaiabla data is not valid at all
		end
		SEND_TO_DEV1 :
		begin
			dma_ack  <= 1'b1;
			count_en <= 1'b1;
			fifo_en  <= 1'b1;
		end
		NOP : ;// dma_ack <= 1'b1;
		END_READ : 
		begin
			end_flag <= 1'b1;
		end
		// Fifo full during Read-op
		FIFO_FULL_RD: 
		begin
			count_en <= 1'b1;  //load dev counter
			count_load <= 1'b1;
			load_dev_or_msp <= 1'b1;
		end
		WAIT_DEV : 
		begin
			// dummy status required since the reading is on 3 clock edges
		end
		EMPTY_FIFO_READ :
		begin
			count_en <= 1'b1;
			dma_ack  <= 1'b1;
			fifo_en  <= 1'b1;
		end
		RESTORE_MSP_COUNT : 
		begin
			count_en <= 1'b1;  //enable to allow the loading
			count_load <= 1'b1;
			dev_count_reg_en_f <= 1'b1; //save current dev count
			//load_dev_or_msp <= 1'b0;
		end
		
		// =============
		//    Write
		// =============
		READ_DEV0 :
		begin
			out_to_msp <= 1'b1;
			fifo_wr_rd <= 1'b1;			
		end
		READ_DEV1 :
		begin
			dma_ack <= 1'b1;
			count_en <= 1'b1;
			fifo_wr_rd <= 1'b1;
			fifo_en <= 1'b1;
			out_to_msp <= 1'b1;
		end
		WAIT_WRITE :
		begin		
			fifo_wr_rd <= 1'b1;
			out_to_msp <= 1'b1;
		end
		SEND_TO_MEM0 :
		begin
			//count_rst <= 1'b1;
			count_en <= 1'b1; //enable to allow the loading
			count_load <= 1'b1;
			dma_we <= 2'b11;
			mmio_ff_en <= 1'b1;
			out_to_msp <= 1'b1;
			drive_dma_addr <= 1'b1;
		end
		SEND_TO_MEM1 :
		begin
			count_en <= 1'b1;
			dma_en <= 1'b1;
			dma_we <= 2'b11;
			drive_dma_addr <= 1'b1;
			fifo_en <= 1'b1;		
			old_addr_reg_en <= 1'b1;
			out_to_msp <= 1'b1;
		end
		OLD_ADDR_WR :
		begin
			dma_en <= 1'b1;
			dma_we <= 2'b11;
			drive_dma_addr <= 1'b1;
			fifo_en <= 1'b1;
			fifo_old_add_flag <= 1'b1;
			mux_old_addr <= 1'b1; 
			out_to_msp <= 1'b1;
		end
		END_WRITE : 
		begin
			drive_dma_addr <= 1'b1;
			end_flag <= 1'b1;
			out_to_msp <= 1'b1; //to correctly write the last data
		end
		
		// Fifo full during Write-op
		FIFO_FULL_WR :
		begin
			count_en <= 1'b1;  //load msp counter
			count_load <= 1'b1;
			load_dev_or_msp <= mmio_flag; // Dirty trick: in case of mmio operation, the msp counter already stores the counting from the read-from-mem operation. Thus, the device register is used to keep track of the write-to-mem op.
			dma_we <= 2'b11;
			drive_dma_addr <= 1'b1;
            mmio_ff_en <= 1'b1; 
			out_to_msp <= 1'b1;
		end
		EMPTY_FIFO_WRITE :
		begin
			count_en <= 1'b1;
			dma_en <= 1'b1;
			dma_we <= 2'b11;
			drive_dma_addr <= 1'b1;
			fifo_en <= 1'b1;		
			old_addr_reg_en <= 1'b1;
			out_to_msp <= 1'b1;
		end
		OLD_ADDR_EMP_FIFO_W :
		begin
			dma_en <= 1'b1;
			dma_we <= 2'b11;
			drive_dma_addr <= 1'b1;
			fifo_en <= 1'b1;
			fifo_old_add_flag <= 1'b1;
			mux_old_addr <= 1'b1; 
			out_to_msp <= 1'b1;
		end
		RESTORE_DEV_COUNT : 
		begin
			count_en <= 1'b1; //enable to allow the loading
			count_load <= 1'b1;
			msp_count_reg_en_f <= 1'b1;
			load_dev_or_msp <= 1'b1;
		end
		default : //Reset on default 
		begin
			addr0_rst <= 1'b1;
			count_rst <= 1'b1;
			dev_count_rst <= 1'b1;
			fifo_rst <= 1'b1;
            mmio_add_rst <= 1'b1;
			mmio_ff_rst <= 1'b1;
			msp_count_rst <= 1'b1;
			old_addr_rst <= 1'b1;
			words_rst <= 1'b1;
		end
		endcase	
end

`ifdef SIM
always @(posedge clk) begin
	$display("DMA: %2s at %2d",state,$time);
	//$display("\t --> Next State %1s",next_state);
end
always @(dev_in) begin
	$display("DMA: Received '%1d' at %2d",dev_in,$time);
end
`endif

	
endmodule 
