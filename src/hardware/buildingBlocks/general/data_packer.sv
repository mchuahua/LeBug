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
  // TODO: move precision logic here as input
 );

    //----------Internal Variables------------
    reg [7:0] firmware_cond       [0:MAX_CHAINS-1] = INITIAL_FIRMWARE_COND;
    reg [DATA_WIDTH-1:0] packed_data [N-1:0]; // Precision changes here
    reg [31:0] packed_counter = 0;
    reg [7:0] firmware [0:MAX_CHAINS-1] = INITIAL_FIRMWARE;
    reg [31:0] total_length;
    reg [31:0] vector_length;
    reg commit;
    reg cond_valid;
    
    wire [DATA_WIDTH-1:0] pack_1 [N-1:0];
    wire [DATA_WIDTH-1:0] pack_M [N-1:0];
    reg [7:0] byte_counter=0;

    localparam PRECISION = 4; // Individual precision size 1/PRECISION
    //TODO: assert checks needed for 0 and PRECISION > DATAWIDTH.

    reg [5:0] precision_counter = 1;

    //-------------Code Start-----------------

    always @(posedge clk) begin
      //Packing is not perfect, otherwise it would be too expensive
      // If we overflow, we just submit things as they are (This may happen if we are mixing precisions)
      if (valid_in==1'b1 && tracing==1'b1 && commit==1'b1 && cond_valid==1'b1) begin
        // If packed data is full (precision counter) and total length is reached, push it out and clear packed_data
        if (PRECISION == precision_counter && total_length >=N) begin
          if (total_length>N) begin 
              vector_out<=packed_data;
              packed_data<=vector_in;
              packed_counter<=vector_length;
          end
          // If not greater than N, then should be N
          else begin 
              if (vector_length==1)
                for(int a = 0; a < N; a++) vector_out[a] <= gen_precision_out.next(packed_data[a], pack_1[a]);
                // vector_out<=pack_1;
              else if (vector_length==M)
                // vector_out<=pack_M;
                for(int a = 0; a < N; a++) vector_out[a] <= gen_precision_out.next(packed_data[a], pack_M[a]);
              // vector_length should be N if neither 1 or M.
              else begin
                for(int a = 0; a < N; a++) vector_out[a] <= gen_precision_out.next(packed_data[a], vector_in[a]);
                // vector_out<=vector_in;
              end
              precision_counter <= 1; // Reset counter for precision packing cycles
                           $display("\tpacked_data: %b %b %b %b %b %b %b %b",packed_data[0],packed_data[1],packed_data[2],packed_data[3],packed_data[4],packed_data[5],packed_data[6],packed_data[7]);

              packed_data<='{default:'{DATA_WIDTH{0}}}; //Clears packed_data by assigning to zero
              packed_counter<=0;
          end
          valid_out<=1;
        end
        // Before packed data is full (precision counter != PRECISION), do two things:
        else begin
          // 1. Increment precision_counter if length is full and reset packed_counter, or increment packed_counter according to vector_length
          if (total_length >= N) begin
            packed_counter <= 0;
            precision_counter <= precision_counter + 1;
          end
          else begin
            packed_counter <= total_length;
          end
          // 2. Pack according to precision
          if (vector_length == 1) begin
              for(int a = 0; a < N; a++) packed_data[a] <= gen_precision_out.next(packed_data[a], pack_1[a]);
              // packed_data_h1 <= pack_1_h2;
            end
          else if (vector_length == M) begin
              for(int a = 0; a < N; a++) packed_data[a] <= gen_precision_out.next(packed_data[a], pack_M[a]);
              // packed_data_h1 <= pack_M_h2;
          end
            // Vector_length is N
          else begin
              for(int a = 0; a < N; a++) packed_data[a] <= gen_precision_out.next(packed_data[a], vector_in[a]);
              // packed_data_h1 <= vector_in_h2;
              $display("\tvector_in: %b %b %b %b %b %b %b %b (valid = %d)",vector_in[0],vector_in[1],vector_in[2],vector_in[3],vector_in[4],vector_in[5],vector_in[6],vector_in[7],valid_in);
              $display("\tpacked_data: %b %b %b %b %b %b %b %b",packed_data[0],packed_data[1],packed_data[2],packed_data[3],packed_data[4],packed_data[5],packed_data[6],packed_data[7]);
          end
          valid_out <= 0;
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
        //  $display("New Cycle:");
        // $display("\tpacked_data: %b %b %b %b %b %b %b %b",packed_data[0],packed_data[1],packed_data[2],packed_data[3],packed_data[4],packed_data[5],packed_data[6],packed_data[7]);
        // $display("\tvector_out: %b %b %b %b %b %b %b %b (valid = %d)",vector_out[0],vector_out[1],vector_out[2],vector_out[3],vector_out[4],vector_out[5],vector_out[6],vector_out[7],valid_out);
        //  $display("\tvector_in: %b %b %b %b %b %b %b %b (valid = %d)",vector_in[0],vector_in[1],vector_in[2],vector_in[3],vector_in[4],vector_in[5],vector_in[6],vector_in[7],valid_in);
        //  $display("\tvector_in: %d %d %d %d %d %d %d %d (valid = %d)",vector_in[0],vector_in[1],vector_in[2],vector_in[3],vector_in[4],vector_in[5],vector_in[6],vector_in[7],valid_in);
        // $display("\tpack_1: %b %b %b %b %b %b %b %b (valid = %d)",pack_1[0],pack_1[1],pack_1[2],pack_1[3],pack_1[4],pack_1[5],pack_1[6],pack_1[7],valid_in);
        // $display("\tpack_M: %b %b %b %b %b %b %b %b (valid = %d)",pack_M[0],pack_M[1],pack_M[2],pack_M[3],pack_M[4],pack_M[5],pack_M[6],pack_M[7],valid_in);

        // TODO: assert ?
        if (valid_out) begin
          $display("PRECISION %d", PRECISION);
          $display("\tvector_out: %b %b %b %b %b %b %b %b (valid = %d)",vector_out[0],vector_out[1],vector_out[2],vector_out[3],vector_out[4],vector_out[5],vector_out[6],vector_out[7],valid_in);
          case (PRECISION)
            2: begin
              $display("\tvector_out: %d %d %d %d %d %d %d %d (valid = %d)",vector_out[0][DATA_WIDTH/PRECISION - 1:0],vector_out[1][DATA_WIDTH/PRECISION - 1:0],vector_out[2][DATA_WIDTH/PRECISION - 1:0],vector_out[3][DATA_WIDTH/PRECISION - 1:0],vector_out[4][DATA_WIDTH/PRECISION - 1:0],vector_out[5][DATA_WIDTH/PRECISION - 1:0],vector_out[6][DATA_WIDTH/PRECISION - 1:0],vector_out[7][DATA_WIDTH/PRECISION - 1:0],valid_in);
            $display("\tvector_out: %d %d %d %d %d %d %d %d (valid = %d)",vector_out[0][DATA_WIDTH-1 : DATA_WIDTH/PRECISION],vector_out[1][DATA_WIDTH-1 : DATA_WIDTH/PRECISION ],vector_out[2][DATA_WIDTH-1 : DATA_WIDTH/PRECISION ],vector_out[3][DATA_WIDTH-1 : DATA_WIDTH/PRECISION ],vector_out[4][DATA_WIDTH -1: DATA_WIDTH/PRECISION ],vector_out[5][DATA_WIDTH -1: DATA_WIDTH/PRECISION ],vector_out[6][DATA_WIDTH -1: DATA_WIDTH/PRECISION ],vector_out[7][DATA_WIDTH-1 : DATA_WIDTH/PRECISION ],valid_in);
            end
            4: begin 
              $display("\tvector_out: %d %d %d %d %d %d %d %d (valid = %d)",vector_out[0][DATA_WIDTH/PRECISION - 1:0],vector_out[1][DATA_WIDTH/PRECISION - 1:0],vector_out[2][DATA_WIDTH/PRECISION - 1:0],vector_out[3][DATA_WIDTH/PRECISION - 1:0],vector_out[4][DATA_WIDTH/PRECISION - 1:0],vector_out[5][DATA_WIDTH/PRECISION - 1:0],vector_out[6][DATA_WIDTH/PRECISION - 1:0],vector_out[7][DATA_WIDTH/PRECISION - 1:0],valid_in);
              $display("\tvector_out: %d %d %d %d %d %d %d %d (valid = %d)",vector_out[0][DATA_WIDTH - 2*DATA_WIDTH/PRECISION -: DATA_WIDTH/PRECISION],vector_out[1][DATA_WIDTH - 2*DATA_WIDTH/PRECISION -: DATA_WIDTH/PRECISION],vector_out[2][DATA_WIDTH - 2*DATA_WIDTH/PRECISION -: DATA_WIDTH/PRECISION],vector_out[3][DATA_WIDTH - 2*DATA_WIDTH/PRECISION -: DATA_WIDTH/PRECISION],vector_out[4][DATA_WIDTH -1: DATA_WIDTH/PRECISION ],vector_out[5][DATA_WIDTH -1: DATA_WIDTH/PRECISION ],vector_out[6][DATA_WIDTH -1: DATA_WIDTH/PRECISION ],vector_out[7][DATA_WIDTH - 2*DATA_WIDTH/PRECISION -: DATA_WIDTH/PRECISION],valid_in);
              $display("\tvector_out: %d %d %d %d %d %d %d %d (valid = %d)",vector_out[0][DATA_WIDTH-DATA_WIDTH/PRECISION -: DATA_WIDTH/PRECISION],vector_out[1][DATA_WIDTH-DATA_WIDTH/PRECISION -: DATA_WIDTH/PRECISION],vector_out[2][DATA_WIDTH-DATA_WIDTH/PRECISION -: DATA_WIDTH/PRECISION],vector_out[3][DATA_WIDTH-DATA_WIDTH/PRECISION -: DATA_WIDTH/PRECISION],vector_out[4][DATA_WIDTH -1: DATA_WIDTH/PRECISION ],vector_out[5][DATA_WIDTH -1: DATA_WIDTH/PRECISION ],vector_out[6][DATA_WIDTH -1: DATA_WIDTH/PRECISION ],vector_out[7][DATA_WIDTH-DATA_WIDTH/PRECISION -: DATA_WIDTH/PRECISION],valid_in);
              $display("\tvector_out: %d %d %d %d %d %d %d %d (valid = %d)",vector_out[0][DATA_WIDTH-1 -: DATA_WIDTH/PRECISION],vector_out[1][DATA_WIDTH-1 -: DATA_WIDTH/PRECISION],vector_out[2][DATA_WIDTH-1 -: DATA_WIDTH/PRECISION],vector_out[3][DATA_WIDTH-1 -: DATA_WIDTH/PRECISION],vector_out[4][DATA_WIDTH -1: DATA_WIDTH/PRECISION ],vector_out[5][DATA_WIDTH -1: DATA_WIDTH/PRECISION ],vector_out[6][DATA_WIDTH -1: DATA_WIDTH/PRECISION ],vector_out[7][DATA_WIDTH-1 -: DATA_WIDTH/PRECISION],valid_in);
            end
            default: $display("\tvector_out: %b %b %b %b %b %b %b %b (valid = %d)",vector_out[0],vector_out[1],vector_out[2],vector_out[3],vector_out[4],vector_out[5],vector_out[6],vector_out[7],valid_in);
          endcase
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


    // x = PRECISION -> {1/x vector_in, x-1/x packed_data}
    generate
      case(PRECISION)
        1: begin: gen_precision_out
          function automatic [DATA_WIDTH-1:0] next;
            input [DATA_WIDTH-1:0] prev;
            input [DATA_WIDTH-1:0] curr;
            next = curr;
          endfunction
        end
        default: begin: gen_precision_out
          function automatic [DATA_WIDTH-1:0] next;
            input [DATA_WIDTH-1:0] prev;
            input [DATA_WIDTH-1:0] curr;
            next = {curr[DATA_WIDTH-1 -: DATA_WIDTH/PRECISION], prev[DATA_WIDTH-1: DATA_WIDTH/PRECISION]};
          endfunction
      end
      endcase
    endgenerate

 
 endmodule 