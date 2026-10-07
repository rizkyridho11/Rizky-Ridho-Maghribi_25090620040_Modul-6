library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Basys3_Calculator is
    Port (
        clk      : in  STD_LOGIC;
        btnC     : in  STD_LOGIC; -- Reset
        btnU     : in  STD_LOGIC; -- Enter Operand A
        btnD     : in  STD_LOGIC; -- Enter Operand B & Eksekusi
        sw       : in  STD_LOGIC_VECTOR (15 downto 0);
        led      : out STD_LOGIC_VECTOR (3 downto 0);
        seg      : out STD_LOGIC_VECTOR (6 downto 0);
        dp       : out STD_LOGIC;
        an       : out STD_LOGIC_VECTOR (3 downto 0)
    );
end Basys3_Calculator;

architecture Behavioral of Basys3_Calculator is

    -- State FSM
    type state_type is (S_WAIT_A, S_WAIT_B, S_COMPUTE, S_SHOW);
    signal current_state : state_type := S_WAIT_A;

    -- Register Data
    signal operand_A   : unsigned(7 downto 0)  := (others => '0');
    signal operand_B   : unsigned(7 downto 0)  := (others => '0');
    signal result_reg  : unsigned(15 downto 0) := (others => '0');
    signal display_val : unsigned(15 downto 0) := (others => '0');
    signal opcode_reg  : std_logic_vector(1 downto 0) := "00";

    -- Sinyal Debounce/Edge Detection Tombol
    signal btnU_q, btnD_q : std_logic := '0';
    signal btnU_pulse     : std_logic := '0';
    signal btnD_pulse     : std_logic := '0';
    signal clk_div        : unsigned(16 downto 0) := (others => '0');

    -- Sinyal BCD (Desimal) & Display
    signal bcd3, bcd2, bcd1, bcd0 : unsigned(3 downto 0)  := (others => '0');
    signal current_digit         : unsigned(3 downto 0)  := (others => '0');
    signal refresh_counter       : unsigned(19 downto 0) := (others => '0');
    signal digit_select          : std_logic_vector(1 downto 0) := "00";

begin

    dp <= '1'; -- Matikan titik desimal (Active Low)

    ----------------------------------------------------------------------------
    -- 1. CLOCK DIVIDER & PULSE DETECTOR TOMBOL
    ----------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            refresh_counter <= refresh_counter + 1;
            clk_div <= clk_div + 1;
            
            if clk_div = 0 then
                btnU_q <= btnU;
                btnD_q <= btnD;
            end if;
        end if;
    end process;

    btnU_pulse <= btnU and (not btnU_q);
    btnD_pulse <= btnD and (not btnD_q);

    ----------------------------------------------------------------------------
    -- 2. FSM KONTROL & ALU
    ----------------------------------------------------------------------------
    process(clk, btnC)
    begin
        if btnC = '1' then
            current_state <= S_WAIT_A;
            operand_A     <= (others => '0');
            operand_B     <= (others => '0');
            result_reg    <= (others => '0');
            opcode_reg    <= "00";
        elsif rising_edge(clk) then
            case current_state is
                when S_WAIT_A =>
                    if btnU_pulse = '1' then
                        operand_A     <= unsigned(sw(7 downto 0));
                        current_state <= S_WAIT_B;
                    end if;

                when S_WAIT_B =>
                    if btnD_pulse = '1' then
                        operand_B     <= unsigned(sw(7 downto 0));
                        opcode_reg    <= sw(15) & sw(14); -- sw(14) dipetakan ke SW13 di XDC
                        current_state <= S_COMPUTE;
                    end if;

                when S_COMPUTE =>
                    case opcode_reg is
                        when "00" => -- Penjumlahan (+)
                            result_reg <= resize(operand_A + operand_B, 16);
                        
                        when "01" => -- Pengurangan (-)
                            if operand_A >= operand_B then
                                result_reg <= resize(operand_A - operand_B, 16);
                            else
                                result_reg <= (others => '0');
                            end if;
                        
                        when "10" => -- Perkalian (x)
                            result_reg <= operand_A * operand_B;
                        
                        when "11" => -- Pembagian (/)
                            if operand_B /= 0 then
                                result_reg <= resize(operand_A / operand_B, 16);
                            else
                                result_reg <= (others => '1');
                            end if;
                        
                        when others =>
                            result_reg <= (others => '0');
                    end case;
                    current_state <= S_SHOW;

                when S_SHOW =>
                    null;

                when others =>
                    current_state <= S_WAIT_A;
            end case;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- 3. INDIKATOR STATE LED (MOORE OUTPUT)
    ----------------------------------------------------------------------------
    process(current_state)
    begin
        case current_state is
            when S_WAIT_A => led <= "0001"; -- LED0
            when S_WAIT_B => led <= "0010"; -- LED1
            when S_COMPUTE=> led <= "0100"; -- LED2
            when S_SHOW   => led <= "1000"; -- LED3
            when others   => led <= "0000";
        end case;
    end process;

    ----------------------------------------------------------------------------
    -- 4. SELEKSI NILAI TAMPILAN (LIVE PREVIEW INPUT ATAU HASIL)
    ----------------------------------------------------------------------------
    process(current_state, sw, result_reg)
    begin
        case current_state is
            when S_WAIT_A | S_WAIT_B =>
                display_val <= resize(unsigned(sw(7 downto 0)), 16);
            when S_COMPUTE | S_SHOW =>
                display_val <= result_reg;
            when others =>
                display_val <= (others => '0');
        end case;
    end process;

    ----------------------------------------------------------------------------
    -- 5. KONVERTER BINER KE DESIMAL (BCD)
    ----------------------------------------------------------------------------
    process(display_val)
        variable temp_val : integer range 0 to 65535;
    begin
        temp_val := to_integer(display_val);
        bcd3 <= to_unsigned((temp_val / 1000) mod 10, 4); -- Ribuan
        bcd2 <= to_unsigned((temp_val / 100) mod 10, 4);  -- Ratusan
        bcd1 <= to_unsigned((temp_val / 10) mod 10, 4);   -- Puluhan
        bcd0 <= to_unsigned(temp_val mod 10, 4);          -- Satuan
    end process;

   ----------------------------------------------------------------------------
    -- 6. MULTIPLEXER SEVEN-SEGMENT (ANODE ACTIVE LOW)
    ----------------------------------------------------------------------------
    digit_select <= std_logic_vector(refresh_counter(19 downto 18));

    process(digit_select, bcd3, bcd2, bcd1, bcd0)
    begin
        case digit_select is
            when "00" =>
                an <= "1110"; -- Digit 0 (Paling Kanan - Satuan, an[0] = '0')
                current_digit <= bcd0;
            when "01" =>
                an <= "1101"; -- Digit 1 (Puluhan, an[1] = '0')
                current_digit <= bcd1;
            when "10" =>
                an <= "1011"; -- Digit 2 (Ratusan, an[2] = '0')
                current_digit <= bcd2;
            when "11" =>
                an <= "0111"; -- Digit 3 (Paling Kiri - Ribuan, an[3] = '0')
                current_digit <= bcd3;
            when others =>
                an <= "1111";
                current_digit <= "0000";
        end case;
    end process;
    ----------------------------------------------------------------------------
    -- 7. DECODER DIGIT DESIMAL KE SEVEN-SEGMENT (ACTIVE LOW)
    ----------------------------------------------------------------------------
    process(current_digit)
    begin
        case current_digit is
            when "0000" => seg <= "1000000"; -- 0
            when "0001" => seg <= "1111001"; -- 1
            when "0010" => seg <= "0100100"; -- 2
            when "0011" => seg <= "0110000"; -- 3
            when "0100" => seg <= "0011001"; -- 4
            when "0101" => seg <= "0100010"; -- 5
            when "0110" => seg <= "0000010"; -- 6
            when "0111" => seg <= "1111000"; -- 7
            when "1000" => seg <= "0000000"; -- 8
            when "1001" => seg <= "0010000"; -- 9
            when others => seg <= "1111111"; -- Mati
        end case;
    end process;

end Behavioral;