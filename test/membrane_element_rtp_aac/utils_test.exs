defmodule Membrane.RTP.AAC.Utils.Test do
  use ExUnit.Case, async: true

  alias Membrane.RTP.AAC.Utils

  describe "make_headers" do
    test "when low bitrate mode" do
      assert match?(
               <<32::16>> <>
                 <<1::6, 0::2>> <>
                 <<2::6, 0::2>> <>
                 <<3::6, 0::2>> <>
                 <<4::6, 0::2>>,
               Utils.make_headers(1..4 |> Enum.to_list(), :lbr)
             )
    end

    test "when high bitrate mode" do
      assert match?(
               <<64::16>> <>
                 <<1::13, 0::3>> <>
                 <<2::13, 0::3>> <>
                 <<3::13, 0::3>> <>
                 <<4::13, 0::3>>,
               Utils.make_headers(1..4 |> Enum.to_list(), :hbr)
             )
    end
  end

  describe "parse_packet" do
    test "when low bitrate mode" do
      aus = [<<1>>, <<2>>]

      packet =
        <<_headers_length = 16::16>> <>
          <<_au1_size = 1::6, _au1_index = 0::2>> <>
          <<_au2_size = 1::6, _au2_delta = 0::2>> <>
          <<1, 2>>

      assert {:ok, aus} ==
               Utils.parse_packet(packet, :lbr)
    end

    test "when high bitrate mode" do
      aus = [<<1>>, <<2>>]

      packet =
        <<_headers_length = 32::16>> <>
          <<_au1_size = 1::13, _au1_index = 0::3>> <>
          <<_au2_size = 1::13, _au2_delta = 0::3>> <>
          <<1, 2>>

      assert {:ok, aus} ==
               Utils.parse_packet(packet, :hbr)
    end

    test "returns an error instead of raising on a malformed packet" do
      # shorter than the AU-headers-length field
      assert {:error, _reason} = Utils.parse_packet(<<>>, :lbr)
      assert {:error, _reason} = Utils.parse_packet(<<0>>, :lbr)
      # AU-headers-length pointing past the end of the payload
      assert {:error, _reason} = Utils.parse_packet(<<1000::16, 1::6, 0::2, 1>>, :lbr)
      # AU header section that is not octet aligned
      assert {:error, _reason} = Utils.parse_packet(<<12::16, 1::6, 0::2, 1>>, :lbr)
      # AU sizes not matching the data section
      assert {:error, _reason} = Utils.parse_packet(<<8::16, 5::6, 0::2, 1>>, :lbr)
    end
  end
end
