//-----------------------------------------------------
// Design Name : Vector Scalar Reduce Unit
// Function    : Reduces an N-size vector into N, M or 1 values
//-----------------------------------------------------

`include "adder_tree.sv"

module  vectorScalarReduceUnit #(
  parameter N=8,
  parameter DATA_WIDTH=32,
  parameter MAX_CHAINS=4,
  parameter PERSONAL_CONFIG_ID=0,
  parameter [7:0] INITIAL_FIRMWARE [0:MAX_CHAINS-1] = '{MAX_CHAINS{0}}
  )
  (
  input logic clk,
  input logic valid_in,
  input logic [1:0] eof_in,
  input logic [1:0] bof_in,
  input logic [$clog2(MAX_CHAINS)-1:0] chainId_in,
  input logic tracing,
  input logic [7:0] configId,
  input logic [7:0] configData,
  input logic [DATA_WIDTH-1:0] vector_in [N-1:0],
  output reg valid_out,
  output reg [DATA_WIDTH-1:0] vector_out [N-1:0],
  output reg [1:0] eof_out,
  output reg [1:0] bof_out,
  output reg [$clog2(MAX_CHAINS)-1:0] chainId_out,
  input logic delta_flag //to match fw logic that connects to datapacker. input is used to prevent multiple drivers even if it isn't being driven
 );

    //----------Internal Variables------------
    reg [7:0] firmware [0:MAX_CHAINS-1] = INITIAL_FIRMWARE;
    wire [DATA_WIDTH-1:0] sum; 
    reg [DATA_WIDTH-1:0] zeros [N-1:0]='{N{0}};
    reg [7:0] byte_counter =0;
    
    // For storing the previous vector for delta computations
    reg [DATA_WIDTH-1:0] vector_prev [N-1:0];
    reg [DATA_WIDTH-1:0] vector_curr [N-1:0];

    //-------------Code Start-----------------
    adderTree #(.N(N), .DATA_WIDTH(DATA_WIDTH))
          adder_tree_inst(.vector(vector_in), .result(sum));

    always @(posedge clk) begin
        // Perform operations normally if we are tracing
        if (tracing==1'b1) begin
          // Assign outputs
          vector_curr<=valid_in;
          // Return N bytes (pass through)
          if (firmware[chainId_in]==8'd0) begin
              vector_curr<=vector_in;
          end
          // Return 1 element (sum of all) zero padded
          else if (firmware[chainId_in]==8'd1) begin
            vector_curr<=zeros;
            vector_curr[0]<= sum;
          end
          vector_prev <= vector_curr;
        end

        // If we are not tracing, we are reconfiguring the instrumentation
        else begin
          valid_out<=0;
          if (configId==PERSONAL_CONFIG_ID) begin
            byte_counter<=byte_counter+1;
            if (byte_counter<MAX_CHAINS)begin
              firmware[byte_counter]=configData;
            end
          end
          else begin
            byte_counter<=0;
          end
        end

        eof_out<=eof_in;
        bof_out<=bof_in;
        chainId_out<=chainId_in;
    end

    // If delta flag is 1, we use current, otherwise we compute delta
    assign vector_out = delta_flag ? vector_curr : vector_prev-vector_curr;
 
endmodule 