library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.std_logic_misc.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

--
-- multiply matrix A(m x p) by  B(p x n), put result in C(m x n)
--
entity mtrx_cross is
  Generic (
    WB_AW   : positive := 16;
    WB_DW   : positive := 16;
    BRAM_AW : positive := 10;
    BRAM_DW : positive := 64;
    -- 2**MTRX_AW is maximum allowable index of matrices
    -- need for correct adder chain instantiation
    MTRX_AW : positive := 5
  );
  Port (
    -- external interrupt pin
    rdy_o : out std_logic;
    
    -- control WB interface
    clk_i : in  std_logic;
    sel_i : in  std_logic;
    stb_i : in  std_logic;
    we_i  : in  std_logic;
    err_o : out std_logic;
    ack_o : out std_logic;
    adr_i : in  std_logic_vector(WB_AW-1 downto 0);
    dat_o : out std_logic_vector(WB_DW-1 downto 0);
    dat_i : in  std_logic_vector(WB_DW-1 downto 0);

    -- BRAM interface
    -- Note: there are no clocks for BRAMs. They are handle in higher level
    bram_adr_a_o : out std_logic_vector(BRAM_AW-1 downto 0);
    bram_adr_b_o : out std_logic_vector(BRAM_AW-1 downto 0);
    bram_adr_c_o : out std_logic_vector(BRAM_AW-1 downto 0);
    
    bram_dat_a_i : in  std_logic_vector(BRAM_DW-1 downto 0);
    bram_dat_b_i : in  std_logic_vector(BRAM_DW-1 downto 0);
    bram_dat_c_o : out std_logic_vector(BRAM_DW-1 downto 0);
    bram_ce_a_o  : out std_logic;
    bram_ce_b_o  : out std_logic;
    bram_ce_c_o  : out std_logic;
    bram_we_o    : out std_logic -- for C bram
  );
end mtrx_cross;


-----------------------------------------------------------------------------

architecture beh of mtrx_cross is
  
  -- operand and result addresses registers
  signal A_adr : std_logic_vector(BRAM_AW-1 downto 0) := (others => '0');
  signal B_adr : std_logic_vector(BRAM_AW-1 downto 0) := (others => '0');
  signal C_adr : std_logic_vector(BRAM_AW-1 downto 0) := (others => '0');
  
  -- multiplicator control signals
  signal mul_nd : std_logic := '0';
  signal mul_ce : std_logic := '0';
  signal mul_rdy : std_logic; -- connected to accumulator nd

  -- matrices size registers
  signal mtrx_m : std_logic_vector (MTRX_AW-1 downto 0) := (others => '0');
  signal mtrx_p : std_logic_vector (MTRX_AW-1 downto 0) := (others => '0');
  signal mtrx_n : std_logic_vector (MTRX_AW-1 downto 0) := (others => '0');
  
  -- counters end of operation detect
  signal end_cnt_m : std_logic_vector(MTRX_AW-1 downto 0) := (others => '0');
  signal end_cnt_n : std_logic_vector(MTRX_AW-1 downto 0) := (others => '0');
  signal the_end   : std_logic := '0'; -- matrix multiplication completed
  
  signal adr_incr_rst : std_logic := '1';
  signal adr_incr_end : std_logic := '0';

  -- accumulator control signals
  signal accum_rst : std_logic := '1';
  signal accum_cnt : STD_LOGIC_VECTOR (MTRX_AW-1 downto 0) := (others => '0');
  signal accum_dat_i : std_logic_vector(BRAM_DW-1 downto 0); -- to multiplicator output
  signal accum_rdy : std_logic := '0'; -- used to increment overall operation count
  
  -- state machine
  type state_t is (IDLE, WAIT_ADR_VALID1, WAIT_ADR_VALID2, WAIT_DATA, ACTIVE, FLUSH1, FLUSH2, FLUSH3);
  signal state : state_t := IDLE;

begin
  
  bram_adr_a_o <= A_adr;
  bram_adr_b_o <= B_adr;
  bram_adr_c_o <= C_adr;
  bram_we_o    <= accum_rdy;

  rdy_o  <= '1' when (state = IDLE) else '0';

  --
  -- addres incrementer
  --
  adr_calc : entity work.adr4mul
    generic map (
      WIDTH => 5
    )
    port map (
      clk_i => clk_i,
      rst_i => adr_incr_rst,
      
      end_o => adr_incr_end,
      
      m_i => mtrx_m,
      p_i => mtrx_p,
      n_i => mtrx_n,
      
      a_adr_o => A_adr,
      b_adr_o => B_adr
    );

  --
  -- multiplicator
  --
  dmul : entity work.dmul
    port map (
      a      => bram_dat_a_i,
      b      => bram_dat_b_i,
      result => accum_dat_i,
      clk    => clk_i,
      ce     => mul_ce,
      rdy    => mul_rdy,
      operation_nd => mul_nd
    );

  -- 
  -- data accumulator
  --
  accumulator : entity work.dadd_chain
    generic map (
      LEN => MTRX_AW
    )
    port map (
      clk_i => clk_i,
      rst_i => accum_rst,
      nd_i  => mul_rdy,
      cnt_i => accum_cnt,
      dat_i => accum_dat_i,
      dat_o => bram_dat_c_o,
      rdy_o => accum_rdy
    );

  --
  -- 1) address increment for result matrix
  -- 2) total operation tracker
  --
  state_tracker : process(clk_i) 
  begin
    if rising_edge(clk_i) then
      the_end <= '0';
      
      if state = WAIT_ADR_VALID1 then
        end_cnt_m <= mtrx_m;
        end_cnt_n <= mtrx_n;
      end if;
      
      if accum_rst = '0' and accum_rdy = '1' then

        C_adr <= C_adr + 1;

        end_cnt_n <= end_cnt_n - 1;
        if (end_cnt_n = 0) then
          end_cnt_n <= mtrx_n;
          end_cnt_m <= end_cnt_m - 1;
        end if;
        
        if end_cnt_m = 0 and end_cnt_n = 0 then
          C_adr <= (others => '0');
          the_end <= '1';

        end if;
      end if;
      
    end if;
  end process;



  --
  -- Main state machine
  --
  main : process(clk_i)
  begin
    --dat_o(WB_AW-1 downto BRAM_AW) <= (others => '0');
    dat_o <= (others => '0');
    
    if rising_edge(clk_i) then
      case state is
      when IDLE =>
        adr_incr_rst <= '1';
        accum_rst    <= '1';
        
        if (stb_i = '1' and sel_i = '1' and we_i = '1') then
          err_o <= '0';
          ack_o <= '1';

          mtrx_m <= dat_i(4 downto 0);
          mtrx_p <= dat_i(9 downto 5);
          mtrx_n <= dat_i(14 downto 10);
      
          accum_cnt <= dat_i(9 downto 5);
          state <= WAIT_ADR_VALID1;
        else
          err_o <= '1';
          ack_o <= '0';
        end if;
        
      when WAIT_ADR_VALID1 =>
        state <= WAIT_ADR_VALID2;
        adr_incr_rst <= '0';
        
      when WAIT_ADR_VALID2 =>
        accum_rst <= '0';
        bram_ce_a_o <= '1';
        bram_ce_b_o <= '1';
        bram_ce_c_o <= '1';
        state <= WAIT_DATA;

      when WAIT_DATA =>
        state <= ACTIVE;
        
      when ACTIVE =>
        mul_nd <= '1';
        mul_ce <= '1';
        if (adr_incr_end = '1') then
          adr_incr_rst <= '1';
          state <= FLUSH1;
        end if;
       
      when FLUSH1 =>
        bram_ce_a_o <= '0';
        bram_ce_b_o <= '0';
        state <= FLUSH2;
        
      when FLUSH2 =>
        mul_nd <= '0';
        state <= FLUSH3;
        
      when FLUSH3 =>
        if (the_end = '1') then
          bram_ce_c_o <= '0';
          mul_ce <= '0';
          state <= IDLE;
        end if;

      end case;
    end if;
  end process;

end beh;
