-- SPDX-License-Identifier: GPL-3.0-or-later
-- Fixed-output binding of pinned Template_MiSTeX ascal. Capture ring occupies
-- logical 0x20000000..0x217fffff; Main framebuffers begin at 0x22000000.
-- Configuration inputs must be transferred atomically into output_clk before
-- they are presented here. RAM transactions go through km_video_axi.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity km_scaler is
    generic (INTERLACED : boolean := false);
    port (
        resetn : in std_logic;
        input_clk, output_clk, memory_clk : in std_logic;
        input_r,input_g,input_b : in std_logic_vector(7 downto 0);
        input_hs,input_vs,input_de,input_ce : in std_logic;
        input_field : in std_logic;
        freeze : in std_logic;
        bob_deint,swblack : in std_logic := '0';
        output_r,output_g,output_b : out std_logic_vector(7 downto 0);
        output_hs,output_vs,output_de : out std_logic;
        fb_enable : in std_logic;
        fb_format : in std_logic_vector(5 downto 0);
        fb_base : in std_logic_vector(31 downto 0);
        fb_width,fb_height : in std_logic_vector(11 downto 0);
        fb_stride : in std_logic_vector(13 downto 0);
        hmin,hmax,vmin,vmax : in std_logic_vector(11 downto 0);
        detected_width,detected_height : out std_logic_vector(11 downto 0);
        avl_waitrequest,avl_readdatavalid : in std_logic;
        avl_readdata : in std_logic_vector(127 downto 0);
        avl_address : out std_logic_vector(27 downto 0);
        avl_burstcount : out std_logic_vector(7 downto 0);
        avl_writedata : out std_logic_vector(127 downto 0);
        avl_byteenable : out std_logic_vector(15 downto 0);
        avl_read,avl_write : out std_logic
    );
end entity;
architecture rtl of km_scaler is
    signal r,g,b : unsigned(7 downto 0);
    signal width,height : natural range 0 to 4095;
begin
    output_r<=std_logic_vector(r); output_g<=std_logic_vector(g); output_b<=std_logic_vector(b);
    -- ascal reports inclusive last-pixel/last-line indices, not dimensions.
    detected_width<=std_logic_vector(to_unsigned((width+1) mod 4096,12));
    detected_height<=std_logic_vector(to_unsigned((height+1) mod 4096,12));
    scaler: entity work.ascal
    generic map (
        MASK=>x"01", RAMBASE=>x"20000000", RAMSIZE=>x"00800000",
        INTER=>INTERLACED, HEADER=>false, DOWNSCALE=>true, DOWNSCALE_NN=>true,
        BYTESWAP=>true, PALETTE=>false, PALETTE2=>false, ADAPTIVE=>false,
        FRAC=>4, OHRES=>2048, IHRES=>1024, N_DW=>128, N_AW=>28, N_BURST=>256
    ) port map (
        reset_na=>resetn,
        i_clk=>input_clk, i_ce=>input_ce, i_r=>unsigned(input_r),
        i_g=>unsigned(input_g), i_b=>unsigned(input_b),
        i_hs=>input_hs, i_vs=>input_vs, i_de=>input_de, i_fl=>input_field,
        bob_deint=>bob_deint, swblack=>swblack,
        iauto=>'1', himin=>0, himax=>0, vimin=>0, vimax=>0,
        i_hdmax=>width, i_vdmax=>height,
        o_clk=>output_clk, o_ce=>'1', o_r=>r,o_g=>g,o_b=>b,
        o_hs=>output_hs,o_vs=>output_vs,o_de=>output_de,
        o_vbl=>open,o_brd=>open,o_lltune=>open,
        o_border=>x"000000", run=>'1',freeze=>freeze,mode=>"01000",format=>"01",
        htotal=>2200,hsstart=>2008,hsend=>2052,hdisp=>1920,
        hmin=>to_integer(unsigned(hmin)),hmax=>to_integer(unsigned(hmax)),
        vtotal=>1125,vsstart=>1084,vsend=>1089,vdisp=>1080,
        vmin=>to_integer(unsigned(vmin)),vmax=>to_integer(unsigned(vmax)),
        vrr=>'0',vrrmax=>0,
        o_fb_ena=>fb_enable,o_fb_format=>unsigned(fb_format),o_fb_base=>unsigned(fb_base),
        o_fb_hsize=>to_integer(unsigned(fb_width)),o_fb_vsize=>to_integer(unsigned(fb_height)),
        o_fb_stride=>unsigned(fb_stride),
        poly_clk=>memory_clk,poly_dw=>(others=>'0'),poly_a=>(others=>'0'),poly_wr=>'0',
        pal1_dr=>open,pal2_dr=>open,
        avl_clk=>memory_clk,avl_waitrequest=>avl_waitrequest,
        avl_readdata=>avl_readdata,avl_readdatavalid=>avl_readdatavalid,
        avl_address=>avl_address,avl_burstcount=>avl_burstcount,
        avl_writedata=>avl_writedata,avl_byteenable=>avl_byteenable,
        avl_read=>avl_read,avl_write=>avl_write
    );
end architecture;
