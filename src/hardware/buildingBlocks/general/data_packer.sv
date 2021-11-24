//-----------------------------------------------------
 // Design Name : Data Packer
 // Function    : Packs data into N values by receiving blocks of N, M or 1 values
 //-----------------------------------------------------

 module  dataPacker #(
  parameter N=8,
  parameter M=2,
  parameter DATA_WIDTH=32,
  parameter MAX_CHAINS=4,
  parameter PERSONAL_CONFIG_ID=0,
  parameter [7:0] INITIAL_FIRMWARE      [0:MAX_CHAINS-1] = '{MAX_CHAINS{0}},
  parameter [7:0] INITIAL_FIRMWARE_COND [0:MAX_CHAINS-1] = '{MAX_CHAINS{0}}
  )
  (
  input logic clk,
  input logic tracing,
  input logic valid_in,
  input logic [1:0] eof_in,
  input logic [1:0] bof_in,
  input logic [$clog2(MAX_CHAINS)-1:0] chainId_in,
  input logic [7:0] configId,
  input logic [7:0] configData,
  input logic [DATA_WIDTH-1:0] vector_in [N-1:0],
  output reg [DATA_WIDTH-1:0] vector_out [N-1:0],
  output reg valid_out
 );

    //TODO: change this to input to change it.
    localparam delta_flag = 0;

    localparam PRECISION = 2; // Only edit this to change precision: (1: full, 2: half, 4: quarter, etc.)
    localparam BLOCK_WIDTH = DATA_WIDTH/PRECISION;
    localparam NS = N*(PRECISION);

    //----------Internal Variables------------
    reg [7:0] firmware_cond [0:MAX_CHAINS-1] = INITIAL_FIRMWARE_COND;
    reg [BLOCK_WIDTH-1:0] packed_data [NS-1:0];
    reg [31:0] packed_counter = 0;
    reg [7:0] firmware [0:MAX_CHAINS-1] = INITIAL_FIRMWARE;
    reg [31:0] total_length;
    reg [31:0] vector_length;
    reg commit;
    reg cond_valid;
    reg [BLOCK_WIDTH-1:0] pack_1 [NS-1:0];
    reg [BLOCK_WIDTH-1:0] pack_M [NS-1:0];
    reg [BLOCK_WIDTH-1:0] pack_delta [N-1:0];
    reg [7:0] byte_counter=0;

    //-------------Code Start-----------------

    always @(posedge clk) begin
      //Packing is not perfect, otherwise it would be too expensive
      // If we overflow, we just submit things as they are (This may happen if we are mixing precisions)
      if (valid_in==1'b1 && tracing==1'b1 && commit==1'b1 && cond_valid==1'b1) begin
        if (total_length>NS) begin
            vector_out<=packed_data;
            packed_data<=vector_in;
            valid_out<=1;
            packed_counter<=vector_length;
        end
        else if (total_length==NS) begin
            if (vector_length==1) begin
              vector_out<=pack_1;
            end
            else if (vector_length==M) begin
              vector_out<=pack_M;
            end
            else begin
              vector_out<=vector_in;
            end
            packed_data<='{default:'{DATA_WIDTH{0}}};
            packed_counter<=0;
            valid_out<=1;
        end
        else begin //no vector overflow
          valid_out<=0;
          if (vector_length==1) begin
            packed_data<=pack_1;
            packed_counter<=total_length;
          end
          else if (vector_length==M) begin
            packed_data<=pack_M;
            packed_counter<=total_length;
          end
        end
      end
      else begin
        valid_out<=0;
        if (tracing==1'b0) begin // If we are not tracing, we are reconfiguring the instrumentation
          if (configId==PERSONAL_CONFIG_ID) begin
            byte_counter<=byte_counter+1;
            if (byte_counter<MAX_CHAINS)begin
              firmware_cond[byte_counter]=configData;
            end
            else if (byte_counter<MAX_CHAINS*2)begin
              firmware[byte_counter]=configData;
            end
          end
          else begin
            byte_counter<=0;
          end
        end
      end
        //$display("New Cycle:");
        //$display("\tvector_in: %0d %0d %0d %0d %0d %0d %0d %0d (valid = %d)",vector_in[0],vector_in[1],vector_in[2],vector_in[3],vector_in[4],vector_in[5],vector_in[6],vector_in[7],valid_in);
        //$display("\tpacked_data: %0d %0d %0d %0d %0d %0d %0d %0d",packed_data[0],packed_data[1],packed_data[2],packed_data[3],packed_data[4],packed_data[5],packed_data[6],packed_data[7]);
        //$display("\tvector_out: %0d %0d %0d %0d %0d %0d %0d %0d (valid = %d)",vector_out[0],vector_out[1],vector_out[2],vector_out[3],vector_out[4],vector_out[5],vector_out[6],vector_out[7],valid_out);
    end

    always @(*) begin
      case (firmware [chainId_in])
        8'd0:    begin vector_length = N; commit=1; end
        8'd1:    begin vector_length = M; commit=1; end
        8'd2:    begin vector_length = 1; commit=1; end
        default: begin vector_length = 0; commit=0; end
      endcase

      // Only perform operation if condition is valid
      // none=0, last=1, notlast=2, first=3, notfirst=4
      if ( (firmware_cond[chainId_in]==8'd0) |
           (firmware_cond[chainId_in][0] & eof_in[0]==1'b1) |
           (firmware_cond[chainId_in][1] & eof_in[0]==1'b0) |
           (firmware_cond[chainId_in][2] & bof_in[0]==1'b1) |
           (firmware_cond[chainId_in][3] & bof_in[0]==1'b0) |
           (firmware_cond[chainId_in][4] & eof_in[1]==1'b1) |
           (firmware_cond[chainId_in][5] & eof_in[1]==1'b0) |
           (firmware_cond[chainId_in][6] & bof_in[1]==1'b1) |
           (firmware_cond[chainId_in][7] & bof_in[1]==1'b0)
           ) begin
        cond_valid = 1'b1;
      end
      else begin
        cond_valid = 1'b0;
      end
    end

    assign total_length = packed_counter+vector_length; // ? Does vector_length need to be changed?

    // Pack delta is a vector of N elements and size BW
    // Pack delta is the input vector in BW instead of DATA_WIDTH
    for(int i = 0; i < N; i++)
      assign pack_delta[i] = vector_in[i][BW-1:0];

    always_comb begin
      // Delta flag == 1 -> full precision
      // Delta flag == 0 -> low precision
      if (delta_flag==1) begin
        // Do things in full precision
        for (int i = 0; i < PRECISION; i++) pack_1[i] = vector_in[0][DATA_WIDTH-1-BLOCK_WIDTH*i -: BLOCK_WIDTH];
        pack_1[NS-1-PRECISION: 0] = packed_data[NS-1:2];
        // pack_1 = {vector_in[0],packed_data[NS-1:2]};
        if (M==N) begin
          for(int i = 0; i < N; i++) begin
            pack_M[i] = vector_in[M]
          end
          pack_M = vector_in[M-1:0];
        end
        else begin
          pack_M = {vector_in[M-1:0],packed_data[NS-1:M*(DATA_WITH/BLOCK_WIDTH)]};
        end
      end
      else begin
        // Do things in low (PRECISION) precision
        pack_1 = {pack_delta[0],packed_data[NS-1:1]};
        pack_M = {pack_delta[M-1:0],packed_data[NS-1:M]};
      end
    end

    // This generate block basically does this:
    // assign [BlOCK_WIDTH-1:0] mem [NS-1:0] = concatenation of different width [DATA_WIDTH-1:0] mem [N-1:0]
    generate
      case(PRECISION)
        1: begin: gen_l2f
          function automatic [DATA_WIDTH-1:0] out [N-1:0];
            input [DATA_WIDTH-1:0] full[N-1:0];
            input [DATA_WIDTH-1:0] low[NS-1:0];
            for(int i = 0; i < N; i++) begin
              next[i] = {}
            end
          endfunction
        end
        default: begin: gen_f2l
          function automatic [BLOCK_WIDTH-1:0] out [NS-1:0];
            input [DATA_WIDTH-1:0] full[N-1:0];
            input [DATA_WIDTH-1:0] low[NS-1:0];
            for (int i = 0; i < N; i+=2) begin
              next[i] = 
              next[i+1] = 
            end
            next = {curr[DATA_WIDTH-1 -: DATA_WIDTH/PRECISION], prev[DATA_WIDTH-1: DATA_WIDTH/PRECISION]};
          endfunction
      end
      endcase
    endgenerate

 endmodule 