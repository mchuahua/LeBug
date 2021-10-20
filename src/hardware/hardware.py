import logging as log
import sys, math, os, shutil, textwrap, subprocess,shlex
from distutils.dir_util import copy_tree
from shutil import copyfile
from firmware.compiler import compiler
from misc.misc import *
import numpy as np
from containers.modelsim.modelsimContainer import modelsimContainer
import time

# Setting Debug level (can be debug, info, warning, error and critical)
log.basicConfig(stream=sys.stderr, level=log.INFO)

''' General settings '''
DEBUG=True

# Run a given command using subprocess
def run(cmd,wait=True):
    proc = subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    if wait:
        proc.wait()

    # Print results
    result = proc.stdout.readlines()+proc.stderr.readlines()
    [ print(r.decode("utf-8"), end = '') for r in result]

class rtlHw():

    # This class describes an instantiated rtlModule
    class rtlInstance():

        # Set parameters
        def setParameters(self,params):
            for p in params:
                instance_parameter_name, instance_parameter_value = p
                module_parameter_names = [item[0] for item in self.module_class.parameter]
                if instance_parameter_name in module_parameter_names:
                    self.parameter[instance_parameter_name]=instance_parameter_value
                else:
                    assert False, f'{instance_parameter_name} is not a parameter from {self.module_class.name}'

        # Connect inputs of instance
        def connectInputs(self,top_module_or_instance=None):
            
            # Check if we are connecting to the top module inputs or to an intance inside top
            if top_module_or_instance == None:
                signals_to_connect = []
            elif type(top_module_or_instance).__name__ == 'rtlInstance':
                signals_to_connect = [top_module_or_instance.instance_output[k] for k in top_module_or_instance.instance_output.keys()]
            elif type(top_module_or_instance).__name__ == 'rtlModule':
                signals_to_connect = top_module_or_instance.input[:]
            else:
                assert False

            # Add aditional signals that don't come from the module we are connecting to
            clock_signal_found=False
            config_signals_found=False
            for i in signals_to_connect:
                if i.name=='clk':
                    clock_signal_found=True
                if i.name=='config':
                    config_signals_found=True
            if not clock_signal_found:
                signals_to_connect.append(struct(name='clk',type='logic',bits=1))
            if not config_signals_found and top_module_or_instance != None:
                signals_to_connect.append(struct(name='tracing_reconfig',type='logic',bits=1,elements=1))
                if self.module_class.configurable_parameters!=0:
                    signals_to_connect.append(struct(name='configData_reconfig',type='logic',bits=8,elements=1))
                    signals_to_connect.append(struct(name='configId_reconfig',type='logic',bits=8,elements=1))

            # Check if number of signals is the same
            assert len(signals_to_connect)==len(self.module_input), "Not the same number of connected signals"

            # Ports map if the first name before the "_" is the same
            portMap={}
            for i in self.module_input:
                for j in signals_to_connect:
                    if i.bits==j.bits and i.name.split("_")[0]==j.name.split("_")[0]:
                        portMap[i.name]=j.name
            assert len(portMap.keys())==len(self.module_input), "Port map failed"
            self.instance_input=portMap


        def __init__(self,module_class,instance_name):
            self.module_class = module_class
            self.name = instance_name
            self.module_input=module_class.input
            self.module_output=module_class.output
            self.instance_input={}
            self.instance_output={}
            self.parameter={}
            self.mem=module_class.mem

            # Map outputs using the name of the instance
            for o in module_class.output:
               self.instance_output[o.name]= struct(name=o.name+"_"+self.name,type=o.type,bits=o.bits,elements=o.elements) 

    # This class describes an RTL module
    class rtlModule():

        # All include files go here
        def include(self,file):
            self.includes.append(file)

        def addInput(self,inputs):
            for i in inputs:
                elements = 1 if len(i)==3 else i[3]
                self.input.append(struct(name=i[0],type=i[1],bits=i[2],elements=elements))

        def addOutput(self,outputs):
            for o in outputs:
                elements = 1 if len(o)==3 else o[3]
                self.output.append(struct(name=o[0],type=o[1],bits=o[2],elements=elements))

        def addParameter(self,params):
            for p in params:
                self.parameter.append(p)

        def addMemory(self,name,depth,width,packed_elements=False,init_values=False):
            # Packed elements is used when we are packing multiple values into a single memory address
            self.mem[name]={}
            self.mem[name]['depth']=depth
            self.mem[name]['width']=width
            self.mem[name]['init_values']=init_values
            self.mem[name]['packed_elements']=packed_elements

        def setAsConfigurable(self,configurable_parameters):
            self.addInput([['tracing','logic',1],['configId','logic',8],['configData','logic',8]])
            self.configurable_parameters=configurable_parameters

        # Recursively adds Modules to module
        def declareModule(self,mod_name):
            if self.included==False:
                self.mod.__dict__[mod_name]=self.parent.rtlModule(self,mod_name)
            else:
                print("Can't declare Modules on imported modules")

        # Lets us know about Modules that have been imported 
        def includeModule(self,mod_name):
            self.declareModule(mod_name)
            self.mod.__dict__[mod_name].included=True

        # Instantiate a given module
        def instantiateModule(self,module_class,instance_name):
            self.inst.__dict__[instance_name]=self.parent.rtlInstance(module_class,instance_name)

        # Dump RTL class into readable RTL
        def dump(self):

            # Append with identation (apdi is apd shifted)
            ident=self.getDepth()*"    "
            rtlCode=[]
            def apd(text):
                lines=text.split("\n")
                for l in lines:
                    rtlCode.append(ident+l)
            def apdi(text):
                lines=text.split("\n")
                for l in lines:
                    rtlCode.append(ident+"    "+l)

            def dumpMifFile(mem):
                for mem_name in mem.keys():
                    m=mem[mem_name]
                    f = open(f"rtl/{mem_name}.mif", "w")
                    f.write(f"Depth = {m['depth']};\n")
                    f.write(f"Width = {m['width']};\n")
                    f.write("Address_radix = dec;\n")
                    f.write("Data_radix = dec;\n")
                    f.write("Content\n")
                    f.write("Begin\n")
                    if m['init_values']!=False:
                        for i in range(m['depth']):
                            # Transform array into a packed value if we are using wide memories to represent arrays
                            if m['packed_elements']!=False:
                                packed_elements= m['packed_elements']
                                element_width = int(m['width']/packed_elements)
                                packed_bits = int(0)
                                for idx, val in enumerate(m['init_values'][i]):
                                    packed_bits=packed_bits | int(val)<<(element_width*idx)
                                f.write(f"{i} : {packed_bits};\n")
                            else:
                                f.write(f"{i} : {m['init_values'][i]};\n")
                    else:
                        f.write(f"[0..{m['depth']-1}] : 0;\n")
                    f.write("End;")
                    f.close()

            # Add includes
            if self.includes!=[]:
                for i in self.includes:
                    apd('`include "'+i+'"')
                apd('')

            # Add declared module
            if self.input+self.output!=[]:
                # Module name
                apd('module  '+self.name)

                # Module parameters
                apd("#(")
                apd(',\n'.join([f'  parameter {parameter_name} = {parameter_value}' for parameter_name, parameter_value in self.parameter]))
                apd(")")

                # Module inputs and outputs
                apd("(")
                apd('\n'.join(f'  input {i.type} [{i.bits}-1:0] {i.name} [{i.elements}-1:0],'.replace("[1-1:0]","") for i in self.input))
                apd(',\n'.join(f'  output {i.type} [{i.bits}-1:0] {i.name} [{i.elements}-1:0]'.replace("[1-1:0]","") for i in self.output))
                apd(');')

                # Do recursive dumps for submodules declared in this module
                for m in self.mod.__dict__.keys():
                    mod=self.mod.__dict__[m]
                    if mod.included==False:
                        rtlCode=rtlCode+mod.dump()

                # Create mif file and output wires
                for i in self.inst.__dict__.keys():
                    inst=self.inst.__dict__[i]

                    # Add mif file 
                    dumpMifFile(inst.mem)
                    
                    # Declare outputs
                    apdi('\n// Outputs of '+str(inst.module_class.name))
                    apdi('\n'.join(f'{value.type} [{value.bits}-1:0] {value.name} [{value.elements}-1:0];'.replace("[1-1:0]","") for key, value in inst.instance_output.items()))

                # Instantiated modules
                for i in self.inst.__dict__.keys():
                    inst=self.inst.__dict__[i]

                    # Print module class name
                    apdi('\n// Instantiating '+str(inst.module_class.name))
                    apdi(inst.module_class.name)

                    # Print parameters
                    if inst.parameter!={}:
                        apdi('#(')
                        apdi(',\n'.join([f'  .{key}({value})' for key, value in inst.parameter.items()]))
                        apdi(')')

                    # Print instance name, inputs and outputs
                    apdi(f'{inst.name}(')
                    apdi('\n'.join([f'  .{key}({value}),' for key, value in inst.instance_input.items()]))
                    apdi(',\n'.join([f'  .{key}({value.name})' for key, value in inst.instance_output.items()]))
                    apdi(");")

                # Create assertions for outputs
                apdi('')
                apdi('\n'.join([f'assign {key}={value};' for key, value in self.output_assignment.items()]))


                # Finish module
                apd('endmodule')

            else:
                print(self.name+" has no inputs/outputs")
        
            return rtlCode 

        # Get depth of instantiated module
        def getDepth(self,d=0):
            if self.parent.__class__.__name__!="rtlHw":
                d=self.parent.getDepth(d)+1
            return d

        # Initializes the RTL file class
        def __init__(self,parent,name):
            self.name=name
            self.parent = parent            # parent Module
            self.includes=[]                # Stores include files
            self.wires=[]                   # Stores wires
            self.regs=[]                    # Stores regs
            self.input=[]                   # Store all inputs logic ports
            self.output=[]                  # Store all outputs logic ports
            self.output_assignment={}       # Describes how outputs are connected to internal signals
            self.parameter=[]               # Store all parameters
            self.included=False             # Is true if the module has been imported
            self.mod=struct()               # Those are the declare modules
            self.inst=struct()              # Those are the instantiated modules
            self.mem={}                     # Array of mems that need the mif files initialized
            self.configurable_parameters=0  # Number of configurable parameters of this module

    def rtlLogicInit(self):
        # Create TOP level module using custom RTL class
        top = self.rtlModule(self,"debugger")
        top.addInput([
            ['clk','logic',1],
            ['uart_rxd','logic',1],
            ['reset','logic',1],
            ['enqueue','logic',1],
            ['eof_in','logic',2],
            ['vector_in','logic','DATA_WIDTH','N']])
        top.addOutput([
            ['uart_txd','logic',1],
            ['vector_out','logic','DATA_WIDTH','N']])
        top.addParameter([
            ['N',self.N],
            ['M',self.M],
            ['DATA_WIDTH',self.DATA_WIDTH],
            ['IB_DEPTH',self.IB_DEPTH],
            ['FUVRF_SIZE',self.FUVRF_SIZE],
            ['VVVRF_SIZE',self.VVVRF_SIZE],
            ['MAX_CHAINS',self.MAX_CHAINS],
            ['TB_SIZE',self.TB_SIZE],
            ['DATA_TYPE',self.DATA_TYPE]])

        # Adds includes to the beginning of the file
        top.include("input_buffer.sv")
        top.include("trace_buffer.sv")
        top.include("data_packer.sv")
        top.include("vector_scalar_reduce_unit.sv")
        top.include("vector_vector_alu.sv")
        top.include("filter_reduce_unit.sv")
        top.include("uart.sv")
        top.include("reconfig_unit.sv")

        # UART module
        top.includeModule("uart")
        top.mod.uart.addInput([
            ['clk','logic',1],
            ['reset','logic',1],
            ['uart_rxd','logic',1],
            ['tx_data','logic',8],
            ['new_tx_data','logic',1]])
        top.mod.uart.addOutput([
            ['uart_txd','logic',1],
            ['tx_busy','logic',1],
            ['rx_data','logic',8],
            ['new_rx_data','logic',1]])
        top.mod.uart.addParameter([
            ['USE_SYNC_RESET',1],
            ['BAUD_LIMIT',15337],
            ['BAUD_FREQ',288]])

        # Reconfig unit module
        top.includeModule("reconfigUnit")
        top.mod.reconfigUnit.addInput([
            ['clk','logic',1],
            ['uart_txd','logic',1],
            ['tx_busy','logic',1],
            ['rx_data','logic',8],
            ['new_rx_data','logic',1],
            ['vector_out_tb','logic','DATA_WIDTH','N']
            ])
        top.mod.reconfigUnit.addOutput([
            ['tx_data','logic',8],
            ['new_tx_data','logic',1],
            ['tracing','logic',1],
            ['configId','logic',8],
            ['configData','logic',8],
            ['tb_mem_address','logic','$clog2(TB_SIZE)']])
        top.mod.reconfigUnit.addParameter([
            ['N'],
            ['DATA_WIDTH'],
            ['TB_SIZE'],
            ['MAX_CHAINS']])

        # Input buffer
        top.includeModule("inputBuffer")
        top.mod.inputBuffer.addInput([
            ['clk','logic',1],
            ['enqueue','logic',1],
            ['eof_in','logic',2],
            ['vector_in','logic','DATA_WIDTH','N']])
        top.mod.inputBuffer.addOutput([
            ['valid_out','logic',1],
            ['eof_out','logic',2],
            ['bof_out','logic',2],
            ['vector_out','logic','DATA_WIDTH','N'],
            ['chainId_out','logic','$clog2(MAX_CHAINS)']])
        top.mod.inputBuffer.addParameter([
            ['N'],
            ['DATA_WIDTH'],
            ['IB_DEPTH'],
            ['MAX_CHAINS'],
            ['INITIAL_FIRMWARE'],
            ['PERSONAL_CONFIG_ID']])
        top.mod.inputBuffer.addMemory("inputBuffer",self.IB_DEPTH,self.DATA_WIDTH*self.N)
        top.mod.inputBuffer.addMemory("inputBuffer_eof",self.IB_DEPTH,2)
        top.mod.inputBuffer.setAsConfigurable(configurable_parameters=4)


        # Filter Reduce Unit
        top.includeModule("filterReduceUnit")
        top.mod.filterReduceUnit.addInput([
            ['clk','logic',1],
            ['valid_in','logic',1],
            ['eof_in','logic',2],
            ['bof_in','logic',2],
            ['chainId_in','logic','$clog2(MAX_CHAINS)'],
            ['vector_in','logic','DATA_WIDTH','N']])
        top.mod.filterReduceUnit.addOutput([
            ['valid_out','logic',1],
            ['eof_out','logic',2],
            ['bof_out','logic',2],
            ['chainId_out','logic','$clog2(MAX_CHAINS)'],
            ['vector_out','logic','DATA_WIDTH','N']])
        top.mod.filterReduceUnit.addParameter([
            ['N'],
            ['M'],
            ['DATA_WIDTH'],
            ['MAX_CHAINS'],
            ['FUVRF_SIZE'],
            ['PERSONAL_CONFIG_ID'],
            ['DATA_TYPE'],
            ['INITIAL_FIRMWARE_FILTER_OP'],
            ['INITIAL_FIRMWARE_FILTER_ADDR'],
            ['INITIAL_FIRMWARE_REDUCE_AXIS']])
        top.mod.filterReduceUnit.setAsConfigurable(configurable_parameters=3)
        top.mod.filterReduceUnit.addMemory("furf",self.FUVRF_SIZE,self.DATA_WIDTH*self.M,packed_elements=self.M)

        # Vector Vector ALU
        top.includeModule("vectorVectorALU")
        top.mod.vectorVectorALU.addInput([
            ['clk','logic',1],
            ['valid_in','logic',1],
            ['eof_in','logic',2],
            ['bof_in','logic',2],
            ['chainId_in','logic','$clog2(MAX_CHAINS)'],
            ['vector_in','logic','DATA_WIDTH','N']])
        top.mod.vectorVectorALU.addOutput([
            ['valid_out','logic',1],
            ['eof_out','logic',2],
            ['bof_out','logic',2],
            ['chainId_out','logic','$clog2(MAX_CHAINS)'],
            ['vector_out','logic','DATA_WIDTH','N']])
        top.mod.vectorVectorALU.addParameter([
            ['N'],
            ['DATA_WIDTH'],
            ['MAX_CHAINS'],
            ['VVVRF_SIZE'],
            ['DATA_TYPE'],
            ['PERSONAL_CONFIG_ID'],
            ['INITIAL_FIRMWARE_OP'],
            ['INITIAL_FIRMWARE_ADDR_RD'],
            ['INITIAL_FIRMWARE_COND'],
            ['INITIAL_FIRMWARE_CACHE'],
            ['INITIAL_FIRMWARE_CACHE_ADDR'],
            ['INITIAL_FIRMWARE_MINICACHE'],
            ['INITIAL_FIRMWARE_CACHE_COND']])
        top.mod.vectorVectorALU.setAsConfigurable(configurable_parameters=7)
        top.mod.vectorVectorALU.addMemory("vvrf",self.VVVRF_SIZE,self.DATA_WIDTH*self.N,packed_elements=self.N)

        # Vector Scalar Reduce unit
        top.includeModule("vectorScalarReduceUnit")
        top.mod.vectorScalarReduceUnit.addInput([
            ['clk','logic',1],
            ['valid_in','logic',1],
            ['eof_in','logic',2],
            ['bof_in','logic',2],
            ['chainId_in','logic','$clog2(MAX_CHAINS)'],
            ['vector_in','logic','DATA_WIDTH','N']])
        top.mod.vectorScalarReduceUnit.addOutput([
            ['valid_out','logic',1],
            ['eof_out','logic',2],
            ['bof_out','logic',2],
            ['chainId_out','logic','$clog2(MAX_CHAINS)'],
            ['vector_out','logic','DATA_WIDTH','N']])
        top.mod.vectorScalarReduceUnit.addParameter([
            ['N'],
            ['DATA_WIDTH'],
            ['MAX_CHAINS'],
            ['PERSONAL_CONFIG_ID'],
            ['INITIAL_FIRMWARE']])
        top.mod.vectorScalarReduceUnit.setAsConfigurable(configurable_parameters=4)

        # Data Packer
        top.includeModule("dataPacker")
        top.mod.dataPacker.addInput([
            ['clk','logic',1],
            ['valid_in','logic',1],
            ['eof_in','logic',2],
            ['bof_in','logic',2],
            ['chainId_in','logic','$clog2(MAX_CHAINS)'],
            ['vector_in','logic','DATA_WIDTH','N']])
        top.mod.dataPacker.addOutput([
            ['valid_out','logic',1],
            ['vector_out','logic','DATA_WIDTH','N']])
        top.mod.dataPacker.addParameter([
            ['N'],
            ['M'],
            ['DATA_WIDTH'],
            ['MAX_CHAINS'],
            ['PERSONAL_CONFIG_ID'],
            ['INITIAL_FIRMWARE'],
            ['INITIAL_FIRMWARE_COND'],
            ['INITIAL_FIRMWARE_PRECISION']])
        top.mod.dataPacker.setAsConfigurable(configurable_parameters=1)

        # TraceBuffer
        top.includeModule("traceBuffer")
        top.mod.traceBuffer.addInput([
            ['clk','logic',1],
            ['valid_in','logic',1],
            ['vector_in','logic','DATA_WIDTH','N'],
            ['tracing','logic',1],
            ['tb_mem_address','logic','$clog2(TB_SIZE)']])
        top.mod.traceBuffer.addOutput([
            ['vector_out','logic','DATA_WIDTH','N']])
        top.mod.traceBuffer.addParameter([
            ['N'],
            ['DATA_WIDTH'],
            ['TB_SIZE']])
        top.mod.traceBuffer.addMemory("traceBuffer",self.TB_SIZE,self.DATA_WIDTH*self.N)

        return top

    def rtlLogicConfig(self):
        top = self.top

        # Convert FW to RTL
        EMPTY_FIRMWARE= "'{MAX_CHAINS{0}}"
        if self.firmware is None:
            IB_INITIAL_FIRMWARE=0
            VSRU_INITIAL_FIRMWARE = EMPTY_FIRMWARE
            DP_INITIAL_FIRMWARE = EMPTY_FIRMWARE
            VVALU_INITIAL_FIRMWARE_OP = EMPTY_FIRMWARE
            VVALU_INITIAL_FIRMWARE_ADDR_RD = EMPTY_FIRMWARE
            VVALU_INITIAL_FIRMWARE_COND = EMPTY_FIRMWARE
            VVALU_INITIAL_FIRMWARE_CACHE = EMPTY_FIRMWARE
            VVALU_INITIAL_FIRMWARE_CACHE_ADDR = EMPTY_FIRMWARE
            VVALU_INITIAL_FIRMWARE_MINICACHE = EMPTY_FIRMWARE
            VVALU_INITIAL_FIRMWARE_CACHE_COND = EMPTY_FIRMWARE
            FRU_INITIAL_FIRMWARE_OP = EMPTY_FIRMWARE
            FRU_INITIAL_FIRMWARE_ADDR = EMPTY_FIRMWARE
            FRU_INITIAL_FIRMWARE_REDUCE_AXIS = EMPTY_FIRMWARE
            DP_INITIAL_FIRMWARE_COND = EMPTY_FIRMWARE
        else:
            
            def encodeDpFirmware(commit,size):
                if commit==0:
                    return 3
                elif size==1:
                    return 2
                elif size==self.M:
                    return 1
                elif size==self.N:
                    return 0
                else:
                    assert False
            def encodeCond(cond1,cond2):
                if cond1['last']:
                    return 1
                elif cond1['notlast']:
                    return 2
                elif cond1['first']:
                    return 4
                elif cond1['notfirst']:
                    return 8
                elif cond2['last']:
                    return 16
                elif cond2['notlast']:
                    return 32
                elif cond2['first']:
                    return 64
                elif cond2['notfirst']:
                    return 128
                else:
                    return 0

            def encodePrecision(precision):
                if precision == 'full':
                    return 0
                elif precision == 'half':
                    return 1
                else:
                    assert False
                
            VSRU_INITIAL_FIRMWARE=str([chain.op for chain in self.firmware['vsru']]).replace("[", "'{").replace("]", "}")
            DP_INITIAL_FIRMWARE = str([encodeDpFirmware(chain.commit,chain.size) for chain in self.firmware['dp']]).replace("[", "'{").replace("]", "}")
            VVALU_INITIAL_FIRMWARE_OP=str([chain.op for chain in self.firmware['vvalu']]).replace("[", "'{").replace("]", "}")
            VVALU_INITIAL_FIRMWARE_ADDR_RD=str([chain.addr for chain in self.firmware['vvalu']]).replace("[", "'{").replace("]", "}")
            VVALU_INITIAL_FIRMWARE_COND=str([encodeCond(chain.cond1,chain.cond2) for chain in self.firmware['vvalu']]).replace("[", "'{").replace("]", "}")
            VVALU_INITIAL_FIRMWARE_CACHE=str([chain.cache for chain in self.firmware['vvalu']]).replace("[", "'{").replace("]", "}")
            VVALU_INITIAL_FIRMWARE_CACHE_ADDR=str([chain.cache_addr for chain in self.firmware['vvalu']]).replace("[", "'{").replace("]", "}")
            VVALU_INITIAL_FIRMWARE_MINICACHE=str([chain.minicache for chain in self.firmware['vvalu']]).replace("[", "'{").replace("]", "}")
            VVALU_INITIAL_FIRMWARE_CACHE_COND=str([encodeCond(chain.cache_cond1,chain.cache_cond2) for chain in self.firmware['vvalu']]).replace("[", "'{").replace("]", "}")
            FRU_INITIAL_FIRMWARE_OP=str([chain.filter for chain in self.firmware['fu']]).replace("[", "'{").replace("]", "}")
            FRU_INITIAL_FIRMWARE_ADDR=str([chain.addr for chain in self.firmware['fu']]).replace("[", "'{").replace("]", "}")
            FRU_INITIAL_FIRMWARE_REDUCE_AXIS=str([chain.axis for chain in self.firmware['mvru']]).replace("[", "'{").replace("]", "}")
            IB_INITIAL_FIRMWARE=self.firmware['valid_chains']
            DP_INITIAL_FIRMWARE_COND = str([encodeCond(chain.cond1,chain.cond2) for chain in self.firmware['dp']]).replace("[", "'{").replace("]", "}")
            DP_INITIAL_FIRMWARE_PRECISION = str([encodePrecision(chain.precision) for chain in self.firmware['dp']]).replace("[", "'{").replace("]", "}")

        # Instantiate modules
        top.instantiateModule(top.mod.uart,"comm")

        top.instantiateModule(top.mod.reconfigUnit,"reconfig")
        top.inst.reconfig.setParameters([
            ['N','N'],
            ['DATA_WIDTH','DATA_WIDTH'],
            ['TB_SIZE','TB_SIZE'],
            ['MAX_CHAINS','MAX_CHAINS']])

        top.instantiateModule(top.mod.inputBuffer,"ib")
        top.inst.ib.setParameters([
            ['N','N'],
            ['DATA_WIDTH','DATA_WIDTH'],
            ['IB_DEPTH','IB_DEPTH'],
            ['PERSONAL_CONFIG_ID','0'],
            ['MAX_CHAINS','MAX_CHAINS'],
            ['INITIAL_FIRMWARE',IB_INITIAL_FIRMWARE]])

        top.instantiateModule(top.mod.filterReduceUnit,"fru")
        top.inst.fru.setParameters([
            ['N','N'],
            ['M','M'],
            ['DATA_WIDTH','DATA_WIDTH'],
            ['MAX_CHAINS','MAX_CHAINS'],
            ['FUVRF_SIZE','FUVRF_SIZE'],
            ['PERSONAL_CONFIG_ID','1'],
            ['DATA_TYPE','DATA_TYPE'],
            ['INITIAL_FIRMWARE_FILTER_OP',FRU_INITIAL_FIRMWARE_OP],
            ['INITIAL_FIRMWARE_FILTER_ADDR',FRU_INITIAL_FIRMWARE_ADDR],
            ['INITIAL_FIRMWARE_REDUCE_AXIS',FRU_INITIAL_FIRMWARE_REDUCE_AXIS]])

        top.instantiateModule(top.mod.vectorVectorALU,"vvalu")
        top.inst.vvalu.setParameters([
            ['N','N'],
            ['DATA_WIDTH','DATA_WIDTH'],
            ['MAX_CHAINS','MAX_CHAINS'],
            ['PERSONAL_CONFIG_ID','2'],
            ['VVVRF_SIZE','VVVRF_SIZE'],
            ['DATA_TYPE','DATA_TYPE'],
            ['INITIAL_FIRMWARE_OP',VVALU_INITIAL_FIRMWARE_OP],
            ['INITIAL_FIRMWARE_ADDR_RD',VVALU_INITIAL_FIRMWARE_ADDR_RD],
            ['INITIAL_FIRMWARE_COND',VVALU_INITIAL_FIRMWARE_COND],
            ['INITIAL_FIRMWARE_CACHE',VVALU_INITIAL_FIRMWARE_CACHE],
            ['INITIAL_FIRMWARE_CACHE_ADDR',VVALU_INITIAL_FIRMWARE_CACHE_ADDR],
            ['INITIAL_FIRMWARE_MINICACHE',VVALU_INITIAL_FIRMWARE_MINICACHE],
            ['INITIAL_FIRMWARE_CACHE_COND',VVALU_INITIAL_FIRMWARE_CACHE_COND]])

        top.instantiateModule(top.mod.vectorScalarReduceUnit,"vsru")
        top.inst.vsru.setParameters([
            ['N','N'],
            ['DATA_WIDTH','DATA_WIDTH'],
            ['MAX_CHAINS','MAX_CHAINS'],
            ['PERSONAL_CONFIG_ID','3'],
            ['INITIAL_FIRMWARE',VSRU_INITIAL_FIRMWARE]])

        top.instantiateModule(top.mod.dataPacker,"dp")
        top.inst.dp.setParameters([
            ['N','N'],
            ['M','M'],
            ['DATA_WIDTH','DATA_WIDTH'],
            ['MAX_CHAINS','MAX_CHAINS'],
            ['PERSONAL_CONFIG_ID','4'],
            ['INITIAL_FIRMWARE',DP_INITIAL_FIRMWARE],
            ['INITIAL_FIRMWARE_COND',DP_INITIAL_FIRMWARE_COND],
            ['INITIAL_FIRMWARE_PRECISION',DP_INITIAL_FIRMWARE_PRECISION]])

        top.instantiateModule(top.mod.traceBuffer,"tb")
        top.inst.tb.setParameters([
            ['N','N'],
            ['DATA_WIDTH','DATA_WIDTH'],
            ['TB_SIZE','TB_SIZE']])

        # Connect fixed modules
        top.inst.comm.instance_input={'clk': 'clk', 
                                    'reset': 'reset', 
                                    'uart_rxd': 'uart_rxd', 
                                    'tx_data': 'tx_data_reconfig', 
                                    'new_tx_data': 'new_tx_data_reconfig'}
        top.inst.reconfig.instance_input={'clk': 'clk', 
                                    'rx_data': 'rx_data_comm', 
                                    'new_rx_data': 'new_rx_data_comm', 
                                    'tx_busy': 'tx_busy_comm',
                                    'vector_out_tb': 'vector_out_tb'}
        top.inst.ib.instance_input={'clk': 'clk', 
                                    'enqueue': 'enqueue', 
                                    'eof_in': 'eof_in', 
                                    'vector_in': 'vector_in', 
                                    'tracing': 'tracing_reconfig', 
                                    'configId': 'configId_reconfig', 
                                    'configData': 'configData_reconfig'}

        # Check if building blocks are not breaking any rules
        if self.BUILDING_BLOCKS[0] != "InputBuffer" or self.BUILDING_BLOCKS[-2]!="DataPacker" or self.BUILDING_BLOCKS[-1]!="TraceBuffer":
            assert False, "Building blocks do not follow order currently supported by the hardware generator"

        # Automatically connect remaining modules
        prev_block = top.inst.ib
        for buildingBlock in self.BUILDING_BLOCKS[1:-2]:
            if buildingBlock=='FilterReduceUnit':
                next_block=top.inst.fru
            elif buildingBlock=='VectorScalarReduce':
                next_block=top.inst.vsru
            elif buildingBlock=='VectorVectorALU':
                next_block=top.inst.vvalu
            else:
                assert False, f"Unknown building block {buildingBlock}"
            next_block.connectInputs(prev_block)
            prev_block=next_block

        top.inst.dp.connectInputs(prev_block)
        top.inst.tb.instance_input={'clk': 'clk', 
                                    'valid_in': 'valid_out_dp', 
                                    'vector_in': 'vector_out_dp', 
                                    'tracing': 'tracing_reconfig',
                                    'tb_mem_address':'tb_mem_address_reconfig'}

        # Assign outputs
        top.output_assignment={'vector_out': 'vector_out_tb','uart_txd':'uart_txd_comm'}


    def testbench(self):
        # Prepare testbench inputs
        tb_inputs=[]
        for i, inp in enumerate(self.testbench_inputs):
            tb_inputs.append("valid = 1;")
            tb_inputs.append(f"eof[0] = {int(inp[1])};")
            if len(inp)>2:
                tb_inputs.append(f"eof[1] = {int(inp[2])};")
            else:
                tb_inputs.append(f"eof[1] = 0;")
            for idx,ele in enumerate(inp[0]):
                tb_inputs.append(f"vector[{idx}]=32'd{ele};")
            tb_inputs.append("#half_period;")
            tb_inputs.append("#half_period;")
            if i!=0:
                tb_inputs.append("toFile();")  
            tb_inputs.append("")
        tb_inputs=("\n"+"    "*4).join(tb_inputs)

        # Prepare testbench steps
        tb_steps=[]
        for i in range(self.steps-len(self.testbench_inputs)+1):
            tb_steps.append("valid = 0;")
            tb_steps.append("#half_period;")
            tb_steps.append("#half_period;")
            tb_steps.append("toFile();")
            tb_steps.append("")
        tb_steps=("\n"+"    "*4).join(tb_steps)

        # Prepare testbench values to save to file
        tb_store=[]
        tb_var_names={}
        for i in self.top.inst.__dict__.keys():
            inst=self.top.inst.__dict__[i]
            tb_var_names[inst.name]=[]
            for o in inst.module_output:
                tb_var_names[inst.name].append([o.name,o.elements])
                if o.elements==1:
                    tb_store.append(f'$fwrite(write_data, "%{"b" if o.bits==1 else "0d"} ",dbg.{inst.name}.{o.name});')
                else:
                    if not o.elements.isnumeric():
                        tb_store.append(f"for (i=0; i<dbg.{inst.name}.{o.elements}; i=i+1) begin")
                    else:
                        tb_store.append(f"for (i=0; i<{o.elements}; i=i+1) begin")
                    tb_store.append(f'\t$fwrite(write_data, "%{"b" if o.bits==1 else "0d"} ",dbg.{inst.name}.{o.name}[i]);')
                    tb_store.append("end")
        tb_store.append('$fdisplay(write_data,"");')
        tb_store=("\n"+"    "*4).join(tb_store)

        # Add includes
        testbench='`include "debugProcessor.sv"\n'

        # Change altsyncram path depending on device family
        if self.DEVICE_FAM == "Cyclone V":
            altsyncram_data_path = "altsyncram_component.altera_syncram_inst.mem_data"
        elif self.DEVICE_FAM == "Stratix 10":
            #altsyncram_data_path = "altsyncram_component.mem_data"
            altsyncram_data_path = "altera_syncram_component.mem_data"
        else:
            assert False, f"Currently only 'Cyclone V' and 'Stratix 10' are supported (received {self.DEVICE_FAM})"
        
        testbench=[testbench+textwrap.dedent(f"""
        `timescale 1 ns/10 ps  // time-unit = 1 ns, precision = 10 ps
        module testbench;

            // Compile-time parameters
            parameter N={self.N};
            parameter DATA_WIDTH={self.DATA_WIDTH};
            parameter IB_DEPTH={self.IB_DEPTH};
            parameter MAX_CHAINS={self.MAX_CHAINS};
            parameter TB_SIZE={self.TB_SIZE};
            parameter FUVRF_SIZE={self.FUVRF_SIZE};
            parameter VVVRF_SIZE={self.VVVRF_SIZE};
            parameter DATA_TYPE={self.DATA_TYPE};
   
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
            {self.top.name} #(
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
                {tb_store}
                end
            endtask

            // Test
            initial begin
                write_data = $fopen("simulation_results.txt");
                
                $display("Test Started");
                {tb_inputs}
                
                {tb_steps}
                
                $fclose(write_data);
                write_data2 = $fopen("simulation_results_tb.txt");
                for (i=0; i<dbg.tb.TB_SIZE; i=i+1) begin
                    tmp = dbg.tb.mem.{altsyncram_data_path}[i];
                    for (j=0; j<N; j=j+1) begin
                        // Verilog you can't have two variable expressions in a range, even if they evaluate to a constant difference.  
                        // Specifically: [j*DATA_WIDTH+DATA_WIDTH-1:j*DATA_WIDTH] should be:[j*DATA_WIDTH +: DATA_WIDTH]
                        $fwrite(write_data2, "%0d ",tmp[DATA_WIDTH*j+:DATA_WIDTH]);
                    end
                    $fwrite(write_data2, "\\n");
                end
                $fclose(write_data2);
                $finish;
            end
        endmodule
        """)]


        self.tb_var_names=tb_var_names
        return testbench

    def generateRtl(self):

        # Create subfolder where all files will be generated
        rtl_folder=os.getcwd()+"/rtl"
        if os.path.isdir(rtl_folder):
            shutil.rmtree(rtl_folder)
        os.mkdir(rtl_folder)
        copy_tree(self.hwFolder+"/buildingBlocks/general", rtl_folder)
        if self.DEVICE_FAM == "Cyclone V":
            copyfile(self.hwFolder+"/buildingBlocks/device-specific/ram_dual_port_cycloneV.sv", rtl_folder+"/ram_dual_port.sv")
        elif self.DEVICE_FAM == "Stratix 10":
            copyfile(self.hwFolder+"/buildingBlocks/device-specific/ram_dual_port_stratix10.sv", rtl_folder+"/ram_dual_port.sv")
        else:
            assert False, f"Currently only 'Cyclone V' and 'Stratix 10' are supported (received {self.DEVICE_FAM})"
        copy_tree(self.hwFolder+"/simulationBlocks", rtl_folder)

        # Writes debugProcessor to file
        f = open(rtl_folder+"/debugProcessor.sv", "w")
        self.rtlLogicConfig()
        for l in self.top.dump():
            f.write(l+"\n")
        f.close()

        # Writes testbench to file
        f = open(rtl_folder+"/testbench.sv", "w")
        for l in self.testbench():
            f.write(l+"\n")
        f.close()

    def config(self,fw):
        #Configure processor
        self.firmware=fw

    # This will run the testbench of the generated hardware and return its results
    def run(self,steps=50,gui=False,log=True):
        # First, generate the RTL
        self.steps=steps
        self.generateRtl()

        # Then, run simulation
        current_folder=os.getcwd()
        rtl_folder=current_folder+"/rtl/"
        os.chdir(rtl_folder)

        modelsim = modelsimContainer(log)
        modelsim.start()
        modelsim.exec('mkdir rtl')
        modelsim.copy(rtl_folder,'modelsim:.')
        modelsim.exec('vlib work',working_directory='/rtl')
        modelsim.exec('vlog altera_mf.v altera_lnsim.sv testbench.sv',working_directory='/rtl')
        if gui:
            print("Opening GUI\n\tMake sure to open socket using this command on your mac:\n\tsocat TCP-LISTEN:6000,reuseaddr,fork UNIX-CLIENT:\\\"$DISPLAY\\\"")
            modelsim.exec('vsim -gui -do "run -all" testbench',working_directory='/rtl')
        else:
            modelsim.exec('vsim -c -do "run -all" testbench',working_directory='/rtl')
        modelsim.copy('modelsim:/rtl/simulation_results.txt','simulation_results.txt')
        modelsim.copy('modelsim:/rtl/simulation_results_tb.txt','simulation_results_tb.txt')
        modelsim.exec('rm -r rtl')
        modelsim.stop()

        # Get results from file back to python
        results={}
        for mod in self.tb_var_names.keys():
                results[mod]={}
                for var_name, elements in self.tb_var_names[mod]:
                    results[mod][var_name]=[]
        f = open("simulation_results.txt", "r")
        for line in f:
            count=0
            l= line.replace("\n","").split(" ")
            for mod in self.tb_var_names.keys():
                for var_name, elements in self.tb_var_names[mod]:
                    if elements=='N':
                        elements=self.N
                    results[mod][var_name].append(l[count:count+elements])
                    count=count+elements

        f = open("simulation_results_tb.txt", "r")
        tb=[]
        for line in f:
            count=0
            l= line.replace(" \n","").split(" ")
            if len(l)>1:
                tb.append(l)
        results['tb']['mem_data']=tb

        # Go back to main directory
        os.chdir(current_folder)

        return results

    def initialize_fu(vals):
        # Check if the values received have the correct size
        assert len(vals)==self.FUVRF_SIZE*M, "FU Initialization failed"

        vals = np.array_split(vals, FUVRF_SIZE)
        # If we are dealing with integers
        if self.DATA_TYPE==0:
            hw_proc.top.mod.filterReduceUnit.mem['furf']['init_values']=vals
        # If we are dealing with fixed-point
        elif self.DATA_TYPE==1:
            hw_proc.top.mod.filterReduceUnit.mem['furf']['init_values']=[floatToEncodedInt(v,DATA_WIDTH) for v in vals]

    def push(self,pushed_values):
        self.testbench_inputs.append(pushed_values)

    def __init__(self,N,M,IB_DEPTH,FUVRF_SIZE,VVVRF_SIZE,TB_SIZE,DATA_WIDTH,MAX_CHAINS,BUILDING_BLOCKS,DATA_TYPE,DEVICE_FAM):
        ''' Verifying parameters '''
        assert math.log(N, 2).is_integer(), "N must be a power of 2" 
        assert math.log(M, 2).is_integer(), "N must be a power of 2" 
        assert M<=N, "M must be less or equal to N" 

        self.N=N
        self.M=M
        self.IB_DEPTH=IB_DEPTH
        self.DATA_WIDTH=DATA_WIDTH
        self.MAX_CHAINS=MAX_CHAINS
        self.TB_SIZE=TB_SIZE
        self.VVVRF_SIZE=VVVRF_SIZE
        self.FUVRF_SIZE=FUVRF_SIZE
        self.DEVICE_FAM=DEVICE_FAM
        self.BUILDING_BLOCKS=BUILDING_BLOCKS
        if DATA_TYPE=='int':
            self.DATA_TYPE=0
        elif DATA_TYPE=='fixed_point':
            self.DATA_TYPE=1
        else:
            print("unknown data type")
            exit()
        self.hwFolder = os.path.dirname(os.path.realpath(__file__))
        self.testbench_inputs=[]    # Stores inputs to testbench
        self.steps=0 # Number of steps for testbench 
        self.tb_var_names = None
        self.compiler = compiler(N,M,MAX_CHAINS)
        self.firmware = None
        self.top=self.rtlLogicInit()
        