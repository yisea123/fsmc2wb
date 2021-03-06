----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    11:04:50 01/19/2016 
-- Design Name: 
-- Module Name:    u16add - beh 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity delay is
  Generic (
    LAT   : positive := 1;
    WIDTH : positive := 1;
    default : std_logic
  );
  Port (
    clk : in  std_logic;
    ce  : in  std_logic;
    di  : in  std_logic_vector(WIDTH-1 downto 0);
    do  : out std_logic_vector(WIDTH-1 downto 0)
  );
end delay;

architecture beh of delay is
  signal pipe : std_logic_vector(WIDTH*LAT-1 downto 0) := (others => default);
begin

  do <= pipe(WIDTH*LAT-1 downto WIDTH*(LAT-1));

  process(clk)
  begin
    if rising_edge(clk) then
      if ce = '1' then
        if LAT = 1 then
          pipe <= di;
        else
          pipe <= pipe(WIDTH*(LAT-1)-1 downto 0) & di;
        end if;
      end if;
    end if;
  end process;
  
end beh;

