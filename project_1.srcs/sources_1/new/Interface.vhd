library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.all;
use IEEE.NUMERIC_STD.ALL;

entity Interface is
    Generic (
            ADDR_WIDTH : integer := 4;
            DATA_WIDTH : integer := 24
            );
    Port ( 
            clk, reset : in STD_LOGIC;
            start : in STD_LOGIC;
            tx : out STD_LOGIC;
            sort_order : in STD_LOGIC
         );
end Interface;

architecture Behavioral of Interface is

    component bin2hex
    Port(
          clk: in std_logic;
          bin: in std_logic_vector(3 downto 0);
          hex_out : out std_logic_vector (3 downto 0)
        );
    end component;
    
    signal done_tick, ready, start_ascii_conv : std_logic := '0';
    
    -- UUT signals
    signal done_sort, request_out : STD_LOGIC := '0';
    signal out_data : STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
    signal uart_conv_data, out_data_hex : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');
    
    signal completion : integer range 0 to 2 := 0;
    
    --BTN_STR_LEN is the length of the array of numbers. 
    signal EVEN_BTN_STR_LEN : natural := (DATA_WIDTH / 8) * 2**ADDR_WIDTH;
    signal ODD_BTN_STR_LEN : natural := ((DATA_WIDTH/8)) * 2**ADDR_WIDTH + 8 ;
    signal data_width_signal : natural := DATA_WIDTH;
    signal BTN_STR_LEN : natural := 2;
    constant INIT_BTN_STR_LEN : natural := 2**ADDR_WIDTH; 
    --constant WELCOME_STR_LEN : natural := 27;
    
    signal strEnd : natural := INIT_BTN_STR_LEN;
    signal strIndex : natural;
    
    signal byte_determine, change_determine : std_logic := '1'; -- 0 = right byte, 1 = left byte; start at 1.
    signal string_begun, skip_next : std_logic := '0'; -- used for controlling out_string_count's increment
    signal bytes_remaining : integer := DATA_WIDTH; -- bytes remaining to be written from data entry
    signal write_opposite : std_logic := '0'; --This is used when an odd number of Hex values are used.
    signal next_write : integer := 0; --This determines if out_string_count is pushed. Used for odd DATA_WIDTHs
    signal byte_written : integer := 8;
    signal first_run : std_logic := '0';
    
    constant RESET_CNTR_MAX : std_logic_vector(17 downto 0) := "110000110101000000";-- 100,000,000 * 0.002 = 200,000 = clk cycles per 2 ms
    constant MAX_STR_LEN : integer := (DATA_WIDTH / 4) * INIT_BTN_STR_LEN; 
    
    type CHAR_ARRAY is array (integer range<>) of std_logic_vector(7 downto 0);
      
    --Contains the current string being sent over uart.
    signal sendStr : CHAR_ARRAY(0 to (MAX_STR_LEN - 1)) := (others => X"00");
    signal tempStr : CHAR_ARRAY(0 to (MAX_STR_LEN - 1)) := (others => X"00");
   
    --UART_TX_CTRL control signals
    signal uartRdy : std_logic;
    signal uartSend : std_logic := '0';
    signal uartData : std_logic_vector (7 downto 0):= "00000000";
    signal uartTX : std_logic;
    
    signal out_string_count : integer  := 0;
    
    --Current uart state signal
    --type UART_STATE_TYPE is (RST_REG, LD_INIT_STR, SEND_CHAR, RDY_LOW, WAIT_RDY, WAIT_BTN, LD_BTN_STR);
    type UART_STATE_TYPE is (RST_REG, SEND_CHAR, RDY_LOW, WAIT_RDY, WAIT_BTN, LD_BTN_STR);
    signal uartState : UART_STATE_TYPE := RST_REG;
    
    
    type STRING_LOAD is (IDLE, LOAD_NEW_CHAR, CHECK_BYTE_STATUS, LOAD_HEX, LOAD_FINAL, DONE);
    signal stringState : STRING_LOAD := IDLE;
    
    signal done_load, reverse_control, one_more_run : std_logic := '0';
    
    --this counter counts the amount of time paused in the UART reset state
    signal reset_cntr : std_logic_vector (17 downto 0) := (others=>'0');
begin

    sorting_algorithm : entity work.sorting_algo(arch)
        generic map(ADDR_WIDTH => ADDR_WIDTH, DATA_WIDTH => DATA_WIDTH)
        port map(clk => clk, start_sort => start, done_sort => done_sort, request_out => request_out, out_data => out_data, reset => reset, 
        sw => sort_order);
   
    uart : entity work.uart_tx_ctrl
        port map(SEND => uartSend, DATA => uartData, CLK => clk, READY => uartRdy, UART_TX => uartTX);
        
    --hex_conversion : bin2hex
    --    port map(clk => clk, bin => out_data_hex, hex_out => uart_conv_data);
        
    BTN_load_process : process(CLK)
    begin
        if rising_edge(clk) then
            if (reset = '1') then
                stringState <= IDLE;
                done_load <= '0';
                completion <= 0;
                out_string_count <= 0;
                request_out <= '0';
                byte_written <= 8;
                byte_determine <= '1';
                
                if (data_width_signal/4) mod 2 = 1 then
                    BTN_STR_LEN <= ODD_BTN_STR_LEN;
                else 
                    BTN_STR_LEN <= EVEN_BTN_STR_LEN;
                end if;
            else
                case stringState is
                    when IDLE =>
                        done_load <= '0';
                        out_string_count <= 0;
                        if done_sort = '1' and completion < 1 then
                            request_out <= '1';
                            stringState <= LOAD_NEW_CHAR;
                        end if;
                    when LOAD_NEW_CHAR =>
                        request_out <= '0';
                        stringState <= LOAD_HEX; 
                    when LOAD_HEX =>
                       first_run <= '1'; 
                       bytes_remaining <= bytes_remaining-4;
                       if bytes_remaining > 0 then          
                            if byte_determine = '1' then
                                tempStr(out_string_count)(7 downto 4) <= out_data(bytes_remaining-1 downto bytes_remaining-4);
                                byte_written <= byte_written - 4;
                                byte_determine <= '0';
                            else
                                tempStr(out_string_count)(3 downto 0) <= out_data(bytes_remaining-1 downto bytes_remaining-4);
                                byte_written <= byte_written - 4;
                                byte_determine <= '1';
                            end if;
                      end if;
                      stringState <= CHECK_BYTE_STATUS;
                    when CHECK_BYTE_STATUS =>
                        if byte_written <= 0 then
                            out_string_count <= out_string_count + 1;
                            byte_written <= 8;
                        end if;
                        if bytes_remaining >= 4 then
                            stringState <= LOAD_NEW_CHAR;
                        else
                            stringState <= LOAD_FINAL; 
                        end if;
                    when LOAD_FINAL =>
                        request_out <= '1';
                        bytes_remaining <= DATA_WIDTH;
                        if out_string_count = BTN_STR_LEN then
                            stringState <= DONE;
                        else
                            stringState <= LOAD_NEW_CHAR;
                        end if;
                    when DONE =>
                        done_load <= '1';
                        completion <= 1;   
                        stringState <= IDLE;            
                end case;
            end if;        
        end if;
    end process;
                 
    process(CLK)
        begin
          if (rising_edge(CLK)) then
            if ((reset_cntr = RESET_CNTR_MAX) or (uartState /= RST_REG)) then
              reset_cntr <= (others=>'0');
            else
              reset_cntr <= reset_cntr + 1;
            end if;
          end if;
        end process;
        
        --Next Uart state logic (states described above)
            next_uartState_process : process (CLK)
            begin
                if (rising_edge(CLK)) then
                    if (reset = '1') then
                        uartState <= RST_REG;
                    else    
                        case uartState is 
                        when RST_REG =>
                            if (reset_cntr = RESET_CNTR_MAX) then
                              uartState <= WAIT_BTN;
                            end if;
                        when SEND_CHAR =>
                            uartState <= RDY_LOW;
                        when RDY_LOW =>
                            uartState <= WAIT_RDY;
                        when WAIT_RDY =>
                            if (uartRdy = '1') then
                                if (strEnd = strIndex) then
                                    uartState <= WAIT_BTN;
                                else
                                    uartState <= SEND_CHAR;
                                end if;
                            end if;
                        when WAIT_BTN =>
                            if (done_load = '1') then
                                uartState <= LD_BTN_STR;
                            end if;
                        when LD_BTN_STR =>
                            uartState <= SEND_CHAR;
                        when others=> --should never be reached
                            uartState <= RST_REG;
                        end case;
                    end if ;
                end if;
            end process;
        
        --Loads the sendStr and strEnd signals when a LD state is
        --is reached.
        string_load_process : process (CLK)
        begin
            if (rising_edge(CLK)) then
                if uartState = LD_BTN_STR then
                    sendStr <= tempStr;
                    strEnd <= BTN_STR_LEN;
                end if;
            end if;
        end process;
        
        --Controls the strIndex signal so that it contains the index
        --of the next character that needs to be sent over uart
        char_count_process : process (CLK)
        begin
            if (rising_edge(CLK)) then
                if (uartState = LD_BTN_STR) then
                    strIndex <= 0;
                elsif uartState = RDY_LOW then
                    strIndex <= strIndex + 1;
                end if;
            end if;
        end process;
        
        --Controls the UART_TX_CTRL signals
        char_load_process : process (CLK)
        begin
            if (rising_edge(CLK)) then
                if (uartState = SEND_CHAR) then
                    uartSend <= '1';
                    uartData <= sendStr(strIndex);
                else
                    uartSend <= '0';
                end if;
            end if;
        end process;
        
    tx <= uartTX;

end Behavioral;
