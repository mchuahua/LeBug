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
  input logic delta_flag,
  output reg [DATA_WIDTH-1:0] vector_out [N-1:0],
  output reg valid_out
 );

    //TODO: change this to input to change it.
    // localparam delta_flag = 1;

    localparam PRECISION = 1; // Only edit this to change precision: (1: full, 2: half, 4: quarter, etc.)
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
            for (int i = 0; i < N; i++) vector_out[i] <= gen_vector.out(i, packed_data);
            for (int i = 0; i < NS; i++) packed_data[i] <= gen_bw.vector_in_to_pack(vector_in[i/PRECISION], i);
            valid_out<=1;
            packed_counter<= vector_length;
        end
        else if (total_length==NS || total_length == N && delta_flag) begin
            if (vector_length==1) begin
              for(int i = 0; i < N; i++) begin
                vector_out[i] <= gen_vector.out(i, pack_1);
              end
            end
            else if (vector_length==M) begin
              for(int i = 0; i < N; i++) begin
                vector_out[i] <= gen_vector.out(i, pack_M);
              end
            end
            else begin
              vector_out<=vector_in;
            end
            packed_data<='{default:'{BLOCK_WIDTH{0}}};
            packed_counter<=0;
            valid_out<=1;
        end
        else begin //no vector overflow
          valid_out<=0;
          if (vector_length==1) begin
            packed_data<=pack_1;
            packed_counter<= total_length;
          end
          else if (vector_length==M) begin
            packed_data<=pack_M;
            packed_counter<= total_length;
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
        $display("New Cycle: %b", delta_flag);
        // $display("\tvector_in: %b %b %b %b %b %b %b %b (valid = %d)",vector_in[0],vector_in[1],vector_in[2],vector_in[3],vector_in[4],vector_in[5],vector_in[6],vector_in[7],valid_in);
        // $display("\tpacked_data: %b %b %b %b %b %b %b %b",packed_data[0],packed_data[1],packed_data[2],packed_data[3],packed_data[4],packed_data[5],packed_data[6],packed_data[7]);
        // $display("\tpack_delta: %b %b %b %b %b %b %b %b",pack_delta[0],pack_delta[1],pack_delta[2],pack_delta[3],pack_delta[4],pack_delta[5],pack_delta[6],pack_delta[7]);
        // $display("\tpack_1: %b %b %b %b %b %b %b %b",pack_1[0],pack_1[1],pack_1[2],pack_1[3],pack_1[4],pack_1[5],pack_1[6],pack_1[7]);
        // $display("\tpack_M: %b %b %b %b %b %b %b %b",pack_M[0],pack_M[1],pack_M[2],pack_M[3],pack_M[4],pack_M[5],pack_M[6],pack_M[7]);
        // $display("\tpack_1: %b %b %b %b %b %b %b %b %b %b %b %b %b %b %b %b",pack_1[0],pack_1[1],pack_1[2],pack_1[3],pack_1[4],pack_1[5],pack_1[6],pack_1[7], pack_1[8],pack_1[9],pack_1[10],pack_1[11],pack_1[12],pack_1[13],pack_1[14],pack_1[15]);
        // $display("\tpack_M: %b %b %b %b %b %b %b %b %b %b %b %b %b %b %b %b",pack_M[0],pack_M[1],pack_M[2],pack_M[3],pack_M[4],pack_M[5],pack_M[6],pack_M[7], pack_M[8],pack_M[9],pack_M[10],pack_M[11],pack_M[12],pack_M[13],pack_M[14],pack_M[15]);
        // $display("\tvector_out: %b %b %b %b %b %b %b %b (valid = %d)",vector_out[0],vector_out[1],vector_out[2],vector_out[3],vector_out[4],vector_out[5],vector_out[6],vector_out[7],valid_out);
        // $display("Vector length %d, total length: %d, packed_counter %d", vector_length, total_length, packed_counter);
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

    always_comb begin
      // Pack delta is a vector of N elements and size BW
      // Pack delta is the input vector in BW instead of DATA_WIDTH
      for(int i = 0; i < N; i++) pack_delta[i] = gen_bw.vector_in_to_pack_delta(vector_in[i]);

      // Delta flag == 1 -> full precision
      // Delta flag == 0 -> low precision
      if (delta_flag==1) begin
        // Do things in full precision
        // Pack 1
        for (int i = 0; i < NS; i++) begin
          if (i < PRECISION)
            pack_1[NS-i-1] = gen_bw.vector_in_to_pack(vector_in[0], i);
          else
            pack_1[i-PRECISION] = packed_data[i];
        end
        // Pack M
        for (int i = 0; i < NS; i++) begin
          if (M == N) 
            pack_M[i] = gen_bw.vector_in_to_pack(vector_in[i/PRECISION], i);
          else if (NS - M*PRECISION - i > 0)
            pack_M[NS-M*PRECISION+i] = gen_bw.vector_in_to_pack(vector_in[i/PRECISION], i);
          else 
            pack_M[i-M*PRECISION] = packed_data[i];
        end 
      end
      else begin
        // Do things in low (PRECISION) precision
        pack_1 = {pack_delta[0],packed_data[NS-1:1]};
        pack_M = {pack_delta[M-1:0],packed_data[NS-1:M]};
      end
    end

    generate
      begin: gen_bw
        function automatic [BLOCK_WIDTH-1:0] vector_in_to_pack_delta;
          input [DATA_WIDTH-1:0] curr;
          vector_in_to_pack_delta[BLOCK_WIDTH-1:0] = curr[BLOCK_WIDTH-1:0];
        endfunction
        function automatic [BLOCK_WIDTH-1:0] vector_in_to_pack;
          input [DATA_WIDTH-1:0] curr;
          input int factor;
          vector_in_to_pack[BLOCK_WIDTH-1:0] = curr[(DATA_WIDTH - BLOCK_WIDTH*(factor%PRECISION)) -1 -: BLOCK_WIDTH];
        endfunction
      end
    endgenerate

    // x = PRECISION -> {1/x vector_in, x-1/x packed_data}
    generate
      case(PRECISION)
        1: begin: gen_vector
          function automatic [DATA_WIDTH-1:0] out;
            input int factor;
            input [BLOCK_WIDTH-1:0] curr[NS-1:0];
            out = curr[factor];
          endfunction
        end
        default: begin: gen_vector
          function automatic [DATA_WIDTH-1:0] out;
            input int factor;
            input [BLOCK_WIDTH-1:0] curr [NS-1:0];
            // out[DATA_WIDTH - BLOCK_WIDTH*(factor%PRECISION))-1 -: BLOCK_WIDTH] = curr;
            for (int i = 0; i < PRECISION; i++)
              out[DATA_WIDTH - BLOCK_WIDTH*(PRECISION-1-i) -1 -: BLOCK_WIDTH] = curr[factor*PRECISION+i];
          endfunction
      end
      endcase
    endgenerate


 endmodule 