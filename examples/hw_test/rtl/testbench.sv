`include "debugProcessor.sv"

`timescale 1 ns/10 ps  // time-unit = 1 ns, precision = 10 ps
module testbench;

    // Compile-time parameters
    parameter N=8;
    parameter DATA_WIDTH=32;
    parameter IB_DEPTH=32;
    parameter MAX_CHAINS=4;
    parameter TB_SIZE=8;
    parameter FUVRF_SIZE=4;
    parameter VVVRF_SIZE=8;
    parameter DATA_TYPE=1;

    // Declare inputs
    reg clk=1'b0;
    reg valid=1'b0;
    reg [1:0] eof=2'b00;
    reg [DATA_WIDTH-1:0] vector [N-1:0];
    reg uart_rxd = 1'b0;
    reg reset = 1'b1;
    wire uart_txd;

    // Declare outputs
    reg [DATA_WIDTH-1:0] vector_out [N-1:0];
    reg valid_out;

    reg [DATA_WIDTH*N-1:0] tmp;
    integer count_1=0;
    integer count_2=0;


    // duration for each bit = 10 * timescale = 10 * 1 ns  = 10ns
    localparam period = 10; 
    localparam half_period = 5; 

    always #half_period clk=~clk; 

    // Instantiate debugger
    debugger #(
      .N(N),
      .DATA_WIDTH(DATA_WIDTH),
      .IB_DEPTH(IB_DEPTH),
      .MAX_CHAINS(MAX_CHAINS),
      .TB_SIZE(TB_SIZE),
      .FUVRF_SIZE(FUVRF_SIZE),
      .VVVRF_SIZE(VVVRF_SIZE),
      .DATA_TYPE(DATA_TYPE)
    )
    dbg(
      .clk(clk),
      .vector_in(vector),
      .enqueue(valid),
      .eof_in(eof),
      .vector_out(vector_out),
      .reset(reset),
      .uart_rxd(uart_rxd),
      .uart_txd(uart_txd)
    );

    //Task to print all content to file
    integer write_data,write_data2,i,j;
    task toFile;
        begin
        $fwrite(write_data, "%b ",dbg.comm.uart_txd);
        $fwrite(write_data, "%b ",dbg.comm.tx_busy);
        $fwrite(write_data, "%0d ",dbg.comm.rx_data);
        $fwrite(write_data, "%b ",dbg.comm.new_rx_data);
        $fwrite(write_data, "%0d ",dbg.reconfig.tx_data);
        $fwrite(write_data, "%b ",dbg.reconfig.new_tx_data);
        $fwrite(write_data, "%b ",dbg.reconfig.tracing);
        $fwrite(write_data, "%0d ",dbg.reconfig.configId);
        $fwrite(write_data, "%0d ",dbg.reconfig.configData);
        $fwrite(write_data, "%0d ",dbg.reconfig.tb_mem_address);
        $fwrite(write_data, "%b ",dbg.ib.valid_out);
        $fwrite(write_data, "%0d ",dbg.ib.eof_out);
        $fwrite(write_data, "%0d ",dbg.ib.bof_out);
        for (i=0; i<dbg.ib.N; i=i+1) begin
        	$fwrite(write_data, "%0d ",dbg.ib.vector_out[i]);
        end
        $fwrite(write_data, "%0d ",dbg.ib.chainId_out);
        $fwrite(write_data, "%b ",dbg.fru.valid_out);
        $fwrite(write_data, "%0d ",dbg.fru.eof_out);
        $fwrite(write_data, "%0d ",dbg.fru.bof_out);
        $fwrite(write_data, "%0d ",dbg.fru.chainId_out);
        for (i=0; i<dbg.fru.N; i=i+1) begin
        	$fwrite(write_data, "%0d ",dbg.fru.vector_out[i]);
        end
        $fwrite(write_data, "%b ",dbg.vvalu.valid_out);
        $fwrite(write_data, "%0d ",dbg.vvalu.eof_out);
        $fwrite(write_data, "%0d ",dbg.vvalu.bof_out);
        $fwrite(write_data, "%0d ",dbg.vvalu.chainId_out);
        for (i=0; i<dbg.vvalu.N; i=i+1) begin
        	$fwrite(write_data, "%0d ",dbg.vvalu.vector_out[i]);
        end
        $fwrite(write_data, "%b ",dbg.vsru.valid_out);
        $fwrite(write_data, "%0d ",dbg.vsru.eof_out);
        $fwrite(write_data, "%0d ",dbg.vsru.bof_out);
        $fwrite(write_data, "%0d ",dbg.vsru.chainId_out);
        for (i=0; i<dbg.vsru.N; i=i+1) begin
        	$fwrite(write_data, "%0d ",dbg.vsru.vector_out[i]);
        end
        $fwrite(write_data, "%b ",dbg.dp.valid_out);
        for (i=0; i<dbg.dp.N; i=i+1) begin
        	$fwrite(write_data, "%0d ",dbg.dp.vector_out[i]);
        end
        for (i=0; i<dbg.tb.N; i=i+1) begin
        	$fwrite(write_data, "%0d ",dbg.tb.vector_out[i]);
        end
        $fdisplay(write_data,"");
        end
    endtask

    // Test
    initial begin
        write_data = $fopen("simulation_results.txt");

        $display("Test Started");
        valid = 1;
        eof[0] = 0;
        eof[1] = 0;
        vector[0]=32'd359670;
        vector[1]=32'd468707;
        vector[2]=32'd395027;
        vector[3]=32'd357095;
        vector[4]=32'd277646;
        vector[5]=32'd423293;
        vector[6]=32'd286777;
        vector[7]=32'd584432;
        #half_period;
        #half_period;

        valid = 1;
        eof[0] = 0;
        eof[1] = 0;
        vector[0]=32'd631546;
        vector[1]=32'd251292;
        vector[2]=32'd518865;
        vector[3]=32'd346617;
        vector[4]=32'd372274;
        vector[5]=32'd606599;
        vector[6]=32'd46554;
        vector[7]=32'd57101;
        #half_period;
        #half_period;
        toFile();

        valid = 1;
        eof[0] = 0;
        eof[1] = 0;
        vector[0]=32'd13250;
        vector[1]=32'd545666;
        vector[2]=32'd509973;
        vector[3]=32'd570171;
        vector[4]=32'd641347;
        vector[5]=32'd523737;
        vector[6]=32'd302435;
        vector[7]=32'd511528;
        #half_period;
        #half_period;
        toFile();


        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();

        valid = 0;
        #half_period;
        #half_period;
        toFile();


        $fclose(write_data);
        write_data2 = $fopen("simulation_results_tb.txt");
        for (i=0; i<dbg.tb.TB_SIZE; i=i+1) begin
            tmp = dbg.tb.mem.altera_syncram_component.mem_data[i];
            for (j=0; j<N; j=j+1) begin
                // Verilog you can't have two variable expressions in a range, even if they evaluate to a constant difference.  
                // Specifically: [j*DATA_WIDTH+DATA_WIDTH-1:j*DATA_WIDTH] should be:[j*DATA_WIDTH +: DATA_WIDTH]
                $fwrite(write_data2, "%0d ",tmp[DATA_WIDTH*j+:DATA_WIDTH]);
            end
            $fwrite(write_data2, "\n");
        end
        $fclose(write_data2);
        $finish;
    end
endmodule

