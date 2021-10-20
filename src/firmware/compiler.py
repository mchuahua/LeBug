from misc.misc import *

#Hardware configurations (that can be done by VLIW instruction)
class compiler():
    # ISA
    def begin_chain(self):
        assert self.chains_created<self.MAX_CHAINS, "Firmware has more chains than the hardware can handle"
        self.chains_created+=1
        no_cond={'last':False,'notlast':False,'first':False,'notfirst':False}
        self.fu    = struct(filter=0,addr=0)
        self.mvru  = struct(axis=0)
        self.vsru  = struct(op=0)
        self.vvalu = struct(op=0,addr=0,cond1=copy(no_cond),cond2=copy(no_cond),cache=0,cache_addr=0,minicache=0,cache_cond1=copy(no_cond),cache_cond2=copy(no_cond))
        self.dp    = struct(commit=0,size=0,cond1=copy(no_cond),cond2=copy(no_cond),precision='full')
    def vv_filter(self,addr):
        self.fu.filter=1
        self.fu.addr=addr
    def m_reduce(self,axis='N'):
        if axis=='N':
            self.mvru.axis=1
        elif axis=='M':
            self.mvru.axis=2
        else:
            assert False, "Unknown axis for instruction m_reduce"
    def v_reduce(self):
        self.vsru.op=1
    def vv_add(self,addr,condition1=None, condition2=None):
        self.vvalu.op=1
        self.vvalu.addr=addr
        self.vvalu.cond1[condition1]=self.__process_condition(condition1)
        self.vvalu.cond2[condition2]=self.__process_condition(condition2)
    def vv_mul(self,addr,condition1=None, condition2=None):
        self.vvalu.op=2
        self.vvalu.addr=addr
        self.vvalu.cond1[condition1]=self.__process_condition(condition1)
        self.vvalu.cond2[condition2]=self.__process_condition(condition2)
    def vv_sub(self,addr,condition1=None, condition2=None):
        self.vvalu.op=3
        self.vvalu.addr=addr
        self.vvalu.cond1[condition1]=self.__process_condition(condition1)
        self.vvalu.cond2[condition2]=self.__process_condition(condition2)
    def vv_max(self,addr,condition1=None, condition2=None):
        self.vvalu.op=4
        self.vvalu.addr=addr
        self.vvalu.cond1[condition1]=self.__process_condition(condition1)
        self.vvalu.cond2[condition2]=self.__process_condition(condition2)
    def v_cache(self,cache_addr,condition1=None, condition2=None):
        self.vvalu.cache=1
        self.vvalu.cache_addr=cache_addr
        self.vvalu.cache_cond1[condition1]=self.__process_condition(condition1)
        self.vvalu.cache_cond2[condition2]=self.__process_condition(condition2)
    def v_mc_load(self):
        if self.vvalu.minicache==0:
            self.vvalu.minicache=1
        else:
            assert False, "Trying to save to load minicache more than once per chain or saving before loading"
    def v_mc_save(self):
        if self.vvalu.minicache==0 or self.vvalu.minicache==1:
            self.vvalu.minicache+=2
        else:
            assert False, "Trying to save to save minicache more than once per chain"
    # Modified to add functionality for full/half precision
    def v_commit(self,size=None,condition1=None, condition2=None, precision='full'):
        if size is None:
            size = self.N
        self.dp.commit=1
        if size==self.N or size==self.M or size==1:
            self.dp.size=size
        else:
            assert False, "Cannot commit "+str(size)+" elements"
        self.dp.cond1[condition1]=self.__process_condition(condition1)
        self.dp.cond2[condition2]=self.__process_condition(condition2)
        self.dp.precision = self.__process_precision(precision)
    def end_chain(self):
        self.firmware['fu'].append(copy(self.fu))
        self.firmware['mvru'].append(copy(self.mvru))
        self.firmware['vsru'].append(copy(self.vsru))
        self.firmware['vvalu'].append(copy(self.vvalu))
        self.firmware['dp'].append(copy(self.dp))
    def compile(self):
        # Make sure we are returning a firmware with MAX_CHAINS chains
        self.firmware['valid_chains'] = self.chains_created
        while self.chains_created!=self.MAX_CHAINS:
            self.begin_chain()
            self.end_chain()
        # Return final firmware    
        return self.firmware

    def __process_condition(self,condition):
        if condition=="last" or condition=="notlast" or condition=="first" or condition=="notfirst" or condition is None :
            return True
        else:
            assert False, "Condition not understood"

    # Only supports full or half precision
    def __process_precision(self,precision):
        if precision=='full' or precision=='half':
            return precision
        else:
            assert False, "Condition not understood"

    def __init__(self,N,M,MAX_CHAINS):
        self.N = N
        self.M = M
        self.MAX_CHAINS=MAX_CHAINS
        self.fu, self.mvru, self.vsru, self.vvalu, self.dp = [],[],[],[],[]
        self.firmware ={"fu":[],"mvru":[],"vsru":[],"vvalu":[],"dp":[],"valid_chains":0}
        self.chains_created = 0
