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
  output reg valid_out,
  // TODO: Needs some bus here for specifying half/full precision ( + FW mod)
  input logic precision
 );

    //----------Internal Variables------------
    reg [7:0] firmware_cond       [0:MAX_CHAINS-1] = INITIAL_FIRMWARE_COND;
    reg [DATA_WIDTH-1:0] packed_data [N-1:0];
    reg [31:0] packed_counter = 0;
    reg [7:0] firmware [0:MAX_CHAINS-1] = INITIAL_FIRMWARE;
    reg [31:0] total_length;
    reg [31:0] vector_length;
    reg commit;
    reg cond_valid;
    wire [DATA_WIDTH-1:0] pack_1 [N-1:0];
    wire [DATA_WIDTH-1:0] pack_M [N-1:0];
    reg [7:0] byte_counter=0;


    reg [DATA_WIDTH / 2 -1 :0] packed_data_h1 [N-1:0];
    reg [DATA_WIDTH / 2 -1 :0] packed_data_h2 [N-1:0];
    reg [DATA_WIDTH / 2 -1 :0] vector_in_h1 [N-1:0];
    reg [DATA_WIDTH / 2 -1 :0] vector_in_h2 [N-1:0];
    reg [DATA_WIDTH / 2 -1 :0] pack_1_h1 [N-1:0];
    reg [DATA_WIDTH / 2 -1 :0] pack_1_h2 [N-1:0];
    reg [DATA_WIDTH / 2 -1 :0] pack_M_h1 [N-1:0];
    reg [DATA_WIDTH / 2 -1 :0] pack_M_h2 [N-1:0];
    //-------------Code Start-----------------

    always @(posedge clk) begin
      //Packing is not perfect, otherwise it would be too expensive
      // If we overflow, we just submit things as they are (This may happen if we are mixing precisions)
      if (valid_in==1'b1 && tracing==1'b1 && commit==1'b1 && cond_valid==1'b1) begin
        if (total_length>N) begin 
            // vector_out<=packed_data;
            for (int i = 0; i < N; i++) vector_out[i] <= {packed_data_h1[i], packed_data_h2[i]};
            // packed_data<=vector_in;
            packed_data_h1<=vector_in_h1;
            packed_data_h2<=vector_in_h2;
            valid_out<=1;
            packed_counter<=vector_length;
        end
        else if (total_length==N) begin 
            if (vector_length==1) begin
              // vector_out<=pack_1;
              for (int i = 0; i < N; i++) vector_out[i] <= {pack_1_h1[i], pack_1_h2[i]};
            end
            else if (vector_length==M) begin
              // vector_out<=pack_M;
              for (int i = 0; i < N; i++) vector_out[i] <= {pack_M_h1[i], pack_M_h2[i]};
            end
            // vector_length should be N
            else begin
              // vector_out<=vector_in;
              for (int b = 0; b < N; b++) vector_out[b] <= {vector_in_h1[b], vector_in_h2[b]};
            end
            packed_data<='{default:'{DATA_WIDTH{0}}}; //Clears packed_data by assigning to zero
            packed_data_h1<='{default:'{DATA_WIDTH/2{0}}}; //Clears packed_data by assigning to zero
            packed_data_h2<='{default:'{DATA_WIDTH/2{0}}}; //Clears packed_data by assigning to zero
            packed_counter<=0;
            valid_out<=1;
        end
        else begin //no vector overflow
          valid_out<=0;
          if (vector_length==1) begin
            packed_data<=pack_1;
            packed_data_h1<=pack_1_h1;
            packed_data_h2<=pack_1_h2;
            packed_counter<=total_length;
          end
          else if (vector_length==M) begin
            packed_data<=pack_M;
            packed_data_h1<=pack_M_h1;
            packed_data_h2<=pack_M_h2;
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
        $display("New Cycle:");
        $display("\tpacked_data: %b %b %b %b %b %b %b %b",packed_data[0],packed_data[1],packed_data[2],packed_data[3],packed_data[4],packed_data[5],packed_data[6],packed_data[7]);
        $display("\tpacked_data_h1: %b %b %b %b %b %b %b %b (valid = %d)",packed_data_h1[0],packed_data_h1[1],packed_data_h1[2],packed_data_h1[3],packed_data_h1[4],packed_data_h1[5],packed_data_h1[6],packed_data_h1[7],valid_in);
        $display("\tpacked_data_h2: %b %b %b %b %b %b %b %b (valid = %d)",packed_data_h2[0],packed_data_h2[1],packed_data_h2[2],packed_data_h2[3],packed_data_h2[4],packed_data_h2[5],packed_data_h2[6],packed_data_h2[7],valid_in);

        //$display("\tvector_out: %0d %0d %0d %0d %0d %0d %0d %0d (valid = %d)",vector_out[0],vector_out[1],vector_out[2],vector_out[3],vector_out[4],vector_out[5],vector_out[6],vector_out[7],valid_out);
        $display("\tvector_in: %b %b %b %b %b %b %b %b (valid = %d)",vector_in[0],vector_in[1],vector_in[2],vector_in[3],vector_in[4],vector_in[5],vector_in[6],vector_in[7],valid_in);
        $display("\tvector_in_h1: %b %b %b %b %b %b %b %b (valid = %d)",vector_in_h1[0],vector_in_h1[1],vector_in_h1[2],vector_in_h1[3],vector_in_h1[4],vector_in_h1[5],vector_in_h1[6],vector_in_h1[7],valid_in);
        $display("\tvector_in_h2: %b %b %b %b %b %b %b %b (valid = %d)",vector_in_h2[0],vector_in_h2[1],vector_in_h2[2],vector_in_h2[3],vector_in_h2[4],vector_in_h2[5],vector_in_h2[6],vector_in_h2[7],valid_in);

        $display("\tpack_1: %b %b %b %b %b %b %b %b (valid = %d)",pack_1[0],pack_1[1],pack_1[2],pack_1[3],pack_1[4],pack_1[5],pack_1[6],pack_1[7],valid_in);
        $display("\tpack_1_h1: %b %b %b %b %b %b %b %b (valid = %d)",pack_1_h1[0],pack_1_h1[1],pack_1_h1[2],pack_1_h1[3],pack_1_h1[4],pack_1_h1[5],pack_1_h1[6],pack_1_h1[7],valid_in);
        $display("\tpack_1_h2: %b %b %b %b %b %b %b %b (valid = %d)",pack_1_h2[0],pack_1_h2[1],pack_1_h2[2],pack_1_h2[3],pack_1_h2[4],pack_1_h2[5],pack_1_h2[6],pack_1_h2[7],valid_in);

        $display("\tpack_M: %b %b %b %b %b %b %b %b (valid = %d)",pack_M[0],pack_M[1],pack_M[2],pack_M[3],pack_M[4],pack_M[5],pack_M[6],pack_M[7],valid_in);
        $display("\tpack_M_h1: %b %b %b %b %b %b %b %b (valid = %d)",pack_M_h1[0],pack_M_h1[1],pack_M_h1[2],pack_M_h1[3],pack_M_h1[4],pack_M_h1[5],pack_M_h1[6],pack_M_h1[7],valid_in);
        $display("\tpack_M_h2: %b %b %b %b %b %b %b %b (valid = %d)",pack_M_h2[0],pack_M_h2[1],pack_M_h2[2],pack_M_h2[3],pack_M_h2[4],pack_M_h2[5],pack_M_h2[6],pack_M_h2[7],valid_in);
        // TODO: assert ?
        if (valid_out) begin
          $display("\tvector_out: %b %b %b %b %b %b %b %b (valid = %d)",vector_out[0],vector_out[1],vector_out[2],vector_out[3],vector_out[4],vector_out[5],vector_out[6],vector_out[7],valid_in);
        end
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

    assign total_length = packed_counter+vector_length;
    assign pack_1 = {vector_in[0],packed_data[N-1:1]};
    assign pack_M = M==N ? {vector_in[M-1:0]}: {vector_in[M-1:0],packed_data[N-1+(M==N):M]};

    generate
      genvar i;
      for (i = 0; i < N; i++) begin : half_precision_vector_in
        assign vector_in_h1[i] = vector_in[i][DATA_WIDTH-1 : DATA_WIDTH / 2 ];
        assign vector_in_h2[i] = vector_in[i][DATA_WIDTH / 2 -1 : 0];
      end
    endgenerate

    // assign pack_1 = {vector_in[0],packed_data[N-1:1]};
    generate
      genvar j;
      for (j = 0; j < N; j++) begin : half_precision_pack1
        // Put in single memory address 0 up top
        if (j == 0) begin
          assign pack_1_h1[N-1] = vector_in[j][DATA_WIDTH-1 : DATA_WIDTH / 2 ];
          assign pack_1_h2[N-1] = vector_in[j][DATA_WIDTH / 2 -1 : 0];
        end
        // Afterwards put in most recent packed_data (aka discard oldest data N-1)
        else begin
          assign pack_1_h1[j-1] = packed_data_h1[j];
          assign pack_1_h2[j-1] = packed_data_h2[j];
        end
      end
    endgenerate

      // assign pack_M = M==N ? {vector_in[M-1:0]}: {vector_in[M-1:0],packed_data[N-1+(M==N):M]};
    generate
      genvar k;
      for (k = 0; k < N; k++) begin : half_precision_packM
        if (M == N) begin
          assign pack_M_h1[k] = vector_in[k][DATA_WIDTH-1 : DATA_WIDTH / 2 ];
          assign pack_M_h2[k] = vector_in[k][DATA_WIDTH / 2 -1 : 0];
        end
        // Put in vector_in for size M
        else if (N - M - k > 0) begin
          assign pack_M_h1[N-M+k] = vector_in[k][DATA_WIDTH-1 : DATA_WIDTH / 2];
          assign pack_M_h2[N-M+k] = vector_in[k][DATA_WIDTH / 2 -1 : 0];
        end
        // Afterwards put in most recent packed_data
        else begin
          assign pack_M_h1[k-M] = packed_data_h1[k];
          assign pack_M_h2[k-M] = packed_data_h2[k];
        end
      end
    endgenerate
    
    
 
 endmodule 