module  simple_dma_device (

// OUTPUTs to uP 
    per_dout,			// Peripheral data output
// OUTPUTs to DMA
	dev_ack,			// Ackowledge for the 2-phase handshake
	dev_out,			// Output to DMA in write op.
	dma_num_words,		// Number of words to be read
	dma_rd_wr,			// Read or write request
	dma_rqst,			// DMA op. request
	dma_start_address,  // Starting address for DMA op.
	mmio_start_address,
// INPUTs from uP
    clk,				// Main system clock
    per_addr,			// Peripheral address
    per_din, 			// Peripheral data input
    per_en,				// Peripheral enable (high active)
    per_we,				// Peripheral write enable (high active)
    reset,				// Main system reset
// INPUTs from DMA
	dev_in,
	dma_ack,
	dma_end_flag,
	dma_error_flag
);


// OUTPUTs
//===================
// OUTPUTs to uP 
output		[15:0] 		per_dout;			// Peripheral data output
// OUTPUTs to DMA
output					dev_ack;			// Ackowledge for the 2-phase handshake
output			[15:0] 	dev_out;			// Data to DMA Controller
output			[15:0]	dma_num_words;		// Number of words to be read
output 					dma_rd_wr;			// Read or write request
output					dma_rqst;			// DMA op. request
output			[15:0]	dma_start_address;	// Starting address for DMA op.
output			[15:0]	mmio_start_address;	// Starting address for MMIO DMA op.
	
// INPUTs
//===================
// INPUTs from uP
input					clk;			// Main system clock
input			[13:0]	per_addr;		// Peripheral address
input			[15:0] 	per_din;		// Peripheral data input
input       	        per_en;         // Peripheral enable (high active)
input	          [1:0] per_we;         // Peripheral write enable (high active)
input   	            reset;	        // Main system reset
// INPUTs from DMA
input			 [15:0] dev_in;			// Data from DMA Controller
input					dma_ack;
input					dma_end_flag;
input                   dma_error_flag;


//=============================================================================
// 1)  PARAMETER DECLARATION
//=============================================================================

// Register base address (must be aligned to decoder bit width)
parameter       [14:0] BASE_ADDR	= 15'h0100;

// Decoder bit width (defines how many bits are considered for address decoding)
parameter              DEC_WD		=  4;

// Register addresses offset
parameter [DEC_WD-1:0] START_ADDR	= 'h00,
                       N_WORDS	    = 'h02,
                       CONFIG 		= 'h04,
                       READ_REG		= 'h06,
                       WRITE_REG    = 'h08,  
                       MMIO_ADDR    = 'h0A;

// Register one-hot decoder utilities
parameter              DEC_SZ      =  (1 << DEC_WD);
parameter [DEC_SZ-1:0] BASE_REG    =  {{DEC_SZ-1{1'b0}}, 1'b1};

// Register one-hot decoder
parameter [DEC_SZ-1:0] START_ADDR_D 	= (BASE_REG << START_ADDR),
                       N_WORDS_D    	= (BASE_REG << N_WORDS),
                       CONFIG_D    		= (BASE_REG << CONFIG),
                       READ_REG_D    	= (BASE_REG << READ_REG),
                       WRITE_REG_D    	= (BASE_REG << WRITE_REG),
                       MMIO_ADDR_D      = (BASE_REG << MMIO_ADDR);


//============================================================================
// 2)  REGISTER DECODER
//============================================================================

// Local register selection
wire              reg_sel   =  per_en & (per_addr[13:DEC_WD-1]==BASE_ADDR[14:DEC_WD]);

// Register local address
wire [DEC_WD-1:0] reg_addr  =  {per_addr[DEC_WD-2:0], 1'b0};

// Register address decode
wire [DEC_SZ-1:0] reg_dec   =  (START_ADDR_D  &  {DEC_SZ{(reg_addr == START_ADDR )}}) |
                               (N_WORDS_D     &  {DEC_SZ{(reg_addr == N_WORDS )}})    |
                               (CONFIG_D      &  {DEC_SZ{(reg_addr == CONFIG )}})     |	 		
                               (READ_REG_D    &  {DEC_SZ{(reg_addr == READ_REG )}})   | 		
                               (WRITE_REG_D   &  {DEC_SZ{(reg_addr == WRITE_REG )}})  |
                               (MMIO_ADDR_D   &  {DEC_SZ{(reg_addr == MMIO_ADDR )}})  ;

// Read/Write probes
wire              reg_write =  |per_we & reg_sel;
wire              reg_read  = ~|per_we & reg_sel;

// Read/Write vectors
wire [DEC_SZ-1:0] reg_wr    = reg_dec & {DEC_SZ{reg_write}};
wire [DEC_SZ-1:0] reg_rd    = reg_dec & {DEC_SZ{reg_read}};


//============================================================================
// 3) REGISTERS
//============================================================================

// START_ADDR Register
//-----------------   
reg  [15:0] start_addr;
wire        start_addr_wr = reg_wr[START_ADDR];

always @ (posedge clk or posedge reset)
  if (reset)              start_addr <= 16'h0000;
  else if (start_addr_wr) start_addr <= per_din;
  else                    start_addr <= start_addr;

assign dma_start_address = start_addr;

   
// N_WORDS Register
//-----------------   
reg  [15:0] n_words;
wire        n_words_wr = reg_wr[N_WORDS];

always @ (posedge clk or posedge reset)
  if (reset)           n_words <= 16'h0000;
  else if (n_words_wr) n_words <= per_din;
  else	               n_words <= n_words;

assign dma_num_words = n_words;


// MMIO_ADDR Register
//-----------------   
reg  [15:0] mmio_addr;
wire        mmio_addr_wr = reg_wr[MMIO_ADDR];

always @ (posedge clk or posedge reset)
  if (reset)              mmio_addr <= 16'h0000;
  else if (mmio_addr_wr) mmio_addr <= per_din;
  else                    mmio_addr <= mmio_addr;

assign mmio_start_address = mmio_addr;
   
// READ_REG: Bridge between DMA Contr. and Dev.- It's Read-only for the CPU!
//---------------------------------------   
reg  [15:0] read_reg;
wire        read_reg_wr    = dma_ack & dma_rqst & dma_rd_wr;
wire		read_reg_reset = reset | config_reg[RESET_REGS];

always @ (posedge clk or posedge read_reg_reset)
  if   (read_reg_reset) read_reg <= 16'h0000;
  else if (read_reg_wr) read_reg <= dev_in; // input from the DMA controller
  else 				    read_reg <= read_reg;


// WRITE_REG: set what has to be written in the memory
//---------------------------------------   
reg [15:0] write_reg;
wire write_reg_wr    = reg_wr[WRITE_REG];
wire write_reg_reset = reset | config_reg[RESET_REGS];

always @(posedge clk or posedge write_reg_reset)
  if (write_reg_reset)   write_reg <= 16'h0000;
  else if (write_reg_wr) write_reg <= per_din;
  else	                 write_reg <= write_reg;
  
//assign dev_out 		= (~dma_rd_wr & dma_rqst) ? write_reg : 16'h0000; (sergio) it's not a problem to have the device always outputing the write_reg value. Memory is still written as usual
assign dev_out 			= write_reg;
		
//=============================================================
// 4) PERIPHERAL DATA BUS - OUT GENERATION
//=============================================================

// Data output mux
//-----------------  
wire [15:0] start_addr_rd  	= start_addr  & {16{reg_rd[START_ADDR]}};
wire [15:0] n_words_rd  	= n_words     & {16{reg_rd[N_WORDS]}};
wire [15:0] config_rd  		= config_reg  & {16{reg_rd[CONFIG]}};
wire [15:0] read_reg_rd		= read_reg    & {16{reg_rd[READ_REG]}};
wire [15:0] write_reg_rd	= write_reg   & {16{reg_rd[WRITE_REG]}};

wire [15:0] per_dout   		= start_addr_rd  |
		                      n_words_rd  	 |
		                      config_rd  	 |
		                   	  write_reg_rd   |
		                   	  read_reg_rd;
		  
		                      
//=============================================================
// 5) CONFIG Register
//=============================================================
// First half of the config register is for CPU configuration; the other half is set by the device itself. (Sergio)
reg  [15:0] config_reg;
wire        config_wr = reg_wr[CONFIG];

localparam START      = 0;
localparam RD_WR      = 2;
localparam NON_ATOMIC = 3;
localparam ACK_SET    = 4;
localparam RESET_REGS = 5;
localparam ERROR_FLAG = 9;
localparam END_OP     = 15;

// -------------------------------------------------------------------
// | END_OP	| - | ~DEV_ACK |  -  | WRITE_OK |  -  | ERROR_FLAG |  -  |
// -------------------------------------------------------------------
// |  15   | 14	|    13    | 12  |    11    | 10  |      9     |  8  |  
// -------------------------------------------------------------------
// -------------------------------------------------------------------
// | - | - | RESET_REGS |  ACK_SET  | NON_ATOMIC | RD_WR | - | START |
// -------------------------------------------------------------------
// | 7 | 6 |     5      |     4     |     3      |   2   | 1 |   0   |
// -------------------------------------------------------------------
always @(posedge clk or posedge reset) begin
   if (reset) begin 
     config_reg[14] <= 1'b0;
     config_reg[12] <= 1'b0;
     config_reg[10] <= 1'b0;
     config_reg[8]  <= 1'b0;
     config_reg[7]  <= 1'b0;
     config_reg[6]  <= 1'b0;
     config_reg[5]  <= 1'b0;
     config_reg[3]  <= 1'b0;
     config_reg[2]  <= 1'b0;
     config_reg[1]  <= 1'b0;
   end
   else if (config_wr) begin
     config_reg[7]  <= per_din[7];
     config_reg[6]  <= per_din[6];
     config_reg[5]  <= per_din[5];
     config_reg[3]  <= per_din[3];
     config_reg[2]  <= per_din[2];
     config_reg[1]  <= per_din[1];
   end 
end

// config_reg[15] - END OPERATION
always @(posedge reset or posedge config_reg[START] or posedge dma_end_flag) begin
	if (reset)                  config_reg[15] <= 1'b0;
	else if (dma_end_flag)      config_reg[15] <= 1'b1;
    else if (config_reg[START]) config_reg[15] <= 1'b0;
    else                        config_reg[15] <= config_reg[15];
end

// config_reg[13] - ~DEV_ACK
always @(posedge reset or posedge config_reg[START] or posedge read_reg_wr or posedge dma_error_flag or posedge config_reg[ACK_SET]) begin
	if (reset)   config_reg[13] <= 1'b0;
    else if (read_reg_wr | dma_error_flag) begin
	     if (config_reg[NON_ATOMIC])      // If non atomic operation is happening
	             config_reg[13] <= 1'b1;  // Autoreset DEV_ACK when reading a datum or on dma_error	
	     end		
	else if (config_reg[ACK_SET]) begin
	     if (config_reg[NON_ATOMIC])      // Request the setting of the DEV_ACK
	             config_reg[13] <= 1'b0;
	     end
    else if (config_reg[START])  
                 config_reg[13] <= 1'b0;
	else         config_reg[13] <= config_reg[13];
end 

// config_reg[11] - WRITE OK
always @(posedge reset or posedge write_reg_wr or posedge dma_ack or posedge config_reg[START]) begin
	if      (reset)              config_reg[11] <= 1'b0;
	else if (write_reg_wr)       config_reg[11] <= 1'b0; //wait for dma_ack
	else if (dma_ack) begin
	     if (~config_reg[RD_WR]) config_reg[11] <= 1'b1; //trigger next read 
	     end
	else if (config_reg[START])  config_reg[11] <= ~config_reg[RD_WR];
	else                         config_reg[11] <= config_reg[11];
end

// config_reg[ACK_SET]
always @(posedge clk or posedge reset or posedge read_reg_wr or posedge dma_error_flag) begin
	if (reset)   config_reg[ACK_SET] <= 1'b0;
    else if (read_reg_wr | dma_error_flag) begin
	     if (config_reg[NON_ATOMIC])           // If non atomic operation is happening		
	             config_reg[ACK_SET] <= 1'b0;  // autoreset DEV_ACK when reading a datum or on dma_error
         end
    else if (config_wr) 
                 config_reg[ACK_SET] <= per_din[ACK_SET]; 
    else         config_reg[ACK_SET] <= config_reg[ACK_SET];
end 

// config_reg[START]
always @(posedge clk or posedge reset or posedge dma_end_flag) begin
	if (reset)             config_reg[START] <= 1'b0;
	else if (dma_end_flag) config_reg[START] <= 1'b0;				
    else if (config_wr)    config_reg[START] <= per_din[START];	
    else                   config_reg[START] <= config_reg[START];
end


//config_reg[ERROR_FLAG]
always @(posedge reset or posedge dma_error_flag or posedge config_reg[START]) begin
	if (reset)                  config_reg[ERROR_FLAG] <= 1'b0;
	else if (dma_error_flag)    config_reg[ERROR_FLAG] <= 1'b1;
	else if (config_reg[START]) config_reg[ERROR_FLAG] <= 1'b0;
end


assign non_atom_ack = (~config_reg[13] & config_reg[RD_WR]) | write_reg_wr;
assign dev_ack      = config_reg[NON_ATOMIC] ? non_atom_ack : 1'b1;
assign dma_rqst     = config_reg[START] & ~config_reg[15] ;
assign dma_rd_wr    = config_reg[RD_WR]; // 1: Read | 0: Write

endmodule 
