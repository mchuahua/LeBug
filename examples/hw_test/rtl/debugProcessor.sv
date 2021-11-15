`include "input_buffer.sv"
`include "trace_buffer.sv"
`include "data_packer.sv"
`include "vector_scalar_reduce_unit.sv"
`include "vector_vector_alu.sv"
`include "filter_reduce_unit.sv"
`include "uart.sv"
`include "reconfig_unit.sv"

module  debugger
#(
  parameter N = 8,
  parameter M = 4,
  parameter DATA_WIDTH = 32,
  parameter IB_DEPTH = 32,
  parameter FUVRF_SIZE = 4,
  parameter VVVRF_SIZE = 8,
  parameter MAX_CHAINS = 4,
  parameter TB_SIZE = 8,
  parameter DATA_TYPE = 0
)
(
  input logic  clk ,
  input logic  uart_rxd ,
  input logic  reset ,
  input logic  enqueue ,
  input logic [2-1:0] eof_in ,
  input logic [DATA_WIDTH-1:0] vector_in [N-1:0],
  output logic  uart_txd ,
  output logic [DATA_WIDTH-1:0] vector_out [N-1:0]
);
    
    // Outputs of uart
    logic  uart_txd_comm ;
    logic  tx_busy_comm ;
    logic [8-1:0] rx_data_comm ;
    logic  new_rx_data_comm ;
    
    // Outputs of reconfigUnit
    logic [8-1:0] tx_data_reconfig ;
    logic  new_tx_data_reconfig ;
    logic  tracing_reconfig ;
    logic [8-1:0] configId_reconfig ;
    logic [8-1:0] configData_reconfig ;
    logic [$clog2(TB_SIZE)-1:0] tb_mem_address_reconfig ;
    
    // Outputs of inputBuffer
    logic  valid_out_ib ;
    logic [2-1:0] eof_out_ib ;
    logic [2-1:0] bof_out_ib ;
    logic [DATA_WIDTH-1:0] vector_out_ib [N-1:0];
    logic [$clog2(MAX_CHAINS)-1:0] chainId_out_ib ;
    
    // Outputs of filterReduceUnit
    logic  valid_out_fru ;
    logic [2-1:0] eof_out_fru ;
    logic [2-1:0] bof_out_fru ;
    logic [$clog2(MAX_CHAINS)-1:0] chainId_out_fru ;
    logic [DATA_WIDTH-1:0] vector_out_fru [N-1:0];
    
    // Outputs of vectorVectorALU
    logic  valid_out_vvalu ;
    logic [2-1:0] eof_out_vvalu ;
    logic [2-1:0] bof_out_vvalu ;
    logic [$clog2(MAX_CHAINS)-1:0] chainId_out_vvalu ;
    logic [DATA_WIDTH-1:0] vector_out_vvalu [N-1:0];
    
    // Outputs of vectorScalarReduceUnit
    logic  valid_out_vsru ;
    logic [2-1:0] eof_out_vsru ;
    logic [2-1:0] bof_out_vsru ;
    logic [$clog2(MAX_CHAINS)-1:0] chainId_out_vsru ;
    logic [DATA_WIDTH-1:0] vector_out_vsru [N-1:0];
    
    // Outputs of dataPacker
    logic  valid_out_dp ;
    logic [DATA_WIDTH-1:0] vector_out_dp [N-1:0];
    
    // Outputs of traceBuffer
    logic [DATA_WIDTH-1:0] vector_out_tb [N-1:0];
    
    // Instantiating uart
    uart
    comm(
      .clk(clk),
      .reset(reset),
      .uart_rxd(uart_rxd),
      .tx_data(tx_data_reconfig),
      .new_tx_data(new_tx_data_reconfig),
      .uart_txd(uart_txd_comm),
      .tx_busy(tx_busy_comm),
      .rx_data(rx_data_comm),
      .new_rx_data(new_rx_data_comm)
    );
    
    // Instantiating reconfigUnit
    reconfigUnit
    #(
      .N(N),
      .DATA_WIDTH(DATA_WIDTH),
      .TB_SIZE(TB_SIZE),
      .MAX_CHAINS(MAX_CHAINS)
    )
    reconfig(
      .clk(clk),
      .rx_data(rx_data_comm),
      .new_rx_data(new_rx_data_comm),
      .tx_busy(tx_busy_comm),
      .vector_out_tb(vector_out_tb),
      .tx_data(tx_data_reconfig),
      .new_tx_data(new_tx_data_reconfig),
      .tracing(tracing_reconfig),
      .configId(configId_reconfig),
      .configData(configData_reconfig),
      .tb_mem_address(tb_mem_address_reconfig)
    );
    
    // Instantiating inputBuffer
    inputBuffer
    #(
      .N(N),
      .DATA_WIDTH(DATA_WIDTH),
      .IB_DEPTH(IB_DEPTH),
      .PERSONAL_CONFIG_ID(0),
      .MAX_CHAINS(MAX_CHAINS),
      .INITIAL_FIRMWARE(2)
    )
    ib(
      .clk(clk),
      .enqueue(enqueue),
      .eof_in(eof_in),
      .vector_in(vector_in),
      .tracing(tracing_reconfig),
      .configId(configId_reconfig),
      .configData(configData_reconfig),
      .valid_out(valid_out_ib),
      .eof_out(eof_out_ib),
      .bof_out(bof_out_ib),
      .vector_out(vector_out_ib),
      .chainId_out(chainId_out_ib)
    );
    
    // Instantiating filterReduceUnit
    filterReduceUnit
    #(
      .N(N),
      .M(M),
      .DATA_WIDTH(DATA_WIDTH),
      .MAX_CHAINS(MAX_CHAINS),
      .FUVRF_SIZE(FUVRF_SIZE),
      .PERSONAL_CONFIG_ID(1),
      .DATA_TYPE(DATA_TYPE),
      .INITIAL_FIRMWARE_FILTER_OP('{0, 0, 0, 0}),
      .INITIAL_FIRMWARE_FILTER_ADDR('{0, 0, 0, 0}),
      .INITIAL_FIRMWARE_REDUCE_AXIS('{0, 0, 0, 0})
    )
    fru(
      .clk(clk),
      .valid_in(valid_out_ib),
      .eof_in(eof_out_ib),
      .bof_in(bof_out_ib),
      .chainId_in(chainId_out_ib),
      .vector_in(vector_out_ib),
      .tracing(tracing_reconfig),
      .configId(configId_reconfig),
      .configData(configData_reconfig),
      .valid_out(valid_out_fru),
      .eof_out(eof_out_fru),
      .bof_out(bof_out_fru),
      .chainId_out(chainId_out_fru),
      .vector_out(vector_out_fru)
    );
    
    // Instantiating vectorVectorALU
    vectorVectorALU
    #(
      .N(N),
      .DATA_WIDTH(DATA_WIDTH),
      .MAX_CHAINS(MAX_CHAINS),
      .PERSONAL_CONFIG_ID(2),
      .VVVRF_SIZE(VVVRF_SIZE),
      .DATA_TYPE(DATA_TYPE),
      .INITIAL_FIRMWARE_OP('{1, 4, 0, 0}),
      .INITIAL_FIRMWARE_ADDR_RD('{0, 1, 0, 0}),
      .INITIAL_FIRMWARE_COND('{8, 128, 0, 0}),
      .INITIAL_FIRMWARE_CACHE('{1, 1, 0, 0}),
      .INITIAL_FIRMWARE_CACHE_ADDR('{0, 1, 0, 0}),
      .INITIAL_FIRMWARE_MINICACHE('{2, 1, 0, 0}),
      .INITIAL_FIRMWARE_CACHE_COND('{0, 1, 0, 0})
    )
    vvalu(
      .clk(clk),
      .valid_in(valid_out_vsru),
      .eof_in(eof_out_vsru),
      .bof_in(bof_out_vsru),
      .chainId_in(chainId_out_vsru),
      .vector_in(vector_out_vsru),
      .tracing(tracing_reconfig),
      .configId(configId_reconfig),
      .configData(configData_reconfig),
      .valid_out(valid_out_vvalu),
      .eof_out(eof_out_vvalu),
      .bof_out(bof_out_vvalu),
      .chainId_out(chainId_out_vvalu),
      .vector_out(vector_out_vvalu)
    );
    
    // Instantiating vectorScalarReduceUnit
    vectorScalarReduceUnit
    #(
      .N(N),
      .DATA_WIDTH(DATA_WIDTH),
      .MAX_CHAINS(MAX_CHAINS),
      .PERSONAL_CONFIG_ID(3),
      .INITIAL_FIRMWARE('{1, 0, 0, 0})
    )
    vsru(
      .clk(clk),
      .valid_in(valid_out_fru),
      .eof_in(eof_out_fru),
      .bof_in(bof_out_fru),
      .chainId_in(chainId_out_fru),
      .vector_in(vector_out_fru),
      .tracing(tracing_reconfig),
      .configId(configId_reconfig),
      .configData(configData_reconfig),
      .valid_out(valid_out_vsru),
      .eof_out(eof_out_vsru),
      .bof_out(bof_out_vsru),
      .chainId_out(chainId_out_vsru),
      .vector_out(vector_out_vsru)
    );
    
    // Instantiating dataPacker
    dataPacker
    #(
      .N(N),
      .M(M),
      .DATA_WIDTH(DATA_WIDTH),
      .MAX_CHAINS(MAX_CHAINS),
      .PERSONAL_CONFIG_ID(4),
      .INITIAL_FIRMWARE('{3, 0, 3, 3}),
      .INITIAL_FIRMWARE_COND('{0, 16, 0, 0})
    )
    dp(
      .clk(clk),
      .valid_in(valid_out_vvalu),
      .eof_in(eof_out_vvalu),
      .bof_in(bof_out_vvalu),
      .chainId_in(chainId_out_vvalu),
      .vector_in(vector_out_vvalu),
      .tracing(tracing_reconfig),
      .configId(configId_reconfig),
      .configData(configData_reconfig),
      .valid_out(valid_out_dp),
      .vector_out(vector_out_dp)
    );
    
    // Instantiating traceBuffer
    traceBuffer
    #(
      .N(N),
      .DATA_WIDTH(DATA_WIDTH),
      .TB_SIZE(TB_SIZE)
    )
    tb(
      .clk(clk),
      .valid_in(valid_out_dp),
      .vector_in(vector_out_dp),
      .tracing(tracing_reconfig),
      .tb_mem_address(tb_mem_address_reconfig),
      .vector_out(vector_out_tb)
    );
    
    assign vector_out=vector_out_tb;
    assign uart_txd=uart_txd_comm;
endmodule
