
 add_fsm_encoding \
       {db_fsm.state_reg} \
       { }  \
       {{000 000} {001 001} {010 010} {011 011} {100 100} {101 101} {110 110} {111 111} }

 add_fsm_encoding \
       {sorting_algo.state_reg} \
       { }  \
       {{0000 000} {0010 001} {0011 101} {0100 110} {0101 111} {0110 010} {0111 011} {1000 100} }

 add_fsm_encoding \
       {Interface.stringState} \
       { }  \
       {{000 000} {001 001} {010 010} {011 011} {100 100} }

 add_fsm_encoding \
       {Interface.uartState} \
       { }  \
       {{000 000} {001 001} {010 010} {011 011} {100 100} {101 101} {110 110} }
