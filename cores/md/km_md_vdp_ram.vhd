-- SPDX-License-Identifier: GPL-3.0-or-later
-- Direct VHDL entities used by the pinned VDP. Synchronous write-first TDP
-- RAM; cross-port same-address collisions are undefined. No reset on arrays.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity DualPortRAM is
    generic(addrbits: integer:=8; databits: integer:=8);
    port(clock: in std_logic;
         address_a: in std_logic_vector(addrbits-1 downto 0);
         data_a: in std_logic_vector(databits-1 downto 0):=(others=>'0');
         wren_a: in std_logic:='0'; q_a: out std_logic_vector(databits-1 downto 0);
         address_b: in std_logic_vector(addrbits-1 downto 0):=(others=>'0');
         data_b: in std_logic_vector(databits-1 downto 0):=(others=>'0');
         wren_b: in std_logic:='0'; q_b: out std_logic_vector(databits-1 downto 0));
end entity;
architecture rtl of DualPortRAM is
    type memory_t is array(0 to 2**addrbits-1) of std_logic_vector(databits-1 downto 0);
    shared variable memory: memory_t:=(others=>(others=>'0'));
    attribute ram_style: string;
    attribute ram_style of memory: variable is "block";
begin
    process(clock) begin
        if rising_edge(clock) then
            if wren_a='1' then memory(to_integer(unsigned(address_a))):=data_a; end if;
            q_a<=memory(to_integer(unsigned(address_a)));
        end if;
    end process;
    process(clock) begin
        if rising_edge(clock) then
            if wren_b='1' then memory(to_integer(unsigned(address_b))):=data_b; end if;
            q_b<=memory(to_integer(unsigned(address_b)));
        end if;
    end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
entity obj_cache is
    port(byteena_a: in std_logic_vector(3 downto 0):=(others=>'1');
         clock: in std_logic:='1'; data: in std_logic_vector(31 downto 0);
         rdaddress,wraddress: in std_logic_vector(6 downto 0);
         wren: in std_logic:='0';q: out std_logic_vector(31 downto 0));
end entity;
architecture rtl of obj_cache is
begin
    lanes: for i in 0 to 3 generate
        signal write_lane: std_logic;
    begin
        write_lane<=wren and byteena_a(i);
        ram: entity work.DualPortRAM generic map(7,8)
            port map(clock,rdaddress,(others=>'0'),'0',q(i*8+7 downto i*8),
                     wraddress,data(i*8+7 downto i*8),write_lane,open);
    end generate;
end architecture;
