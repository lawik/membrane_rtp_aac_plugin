defmodule Membrane.RTP.AAC.Utils do
  @moduledoc """
    This module defines helpers for payloading and depayloading non-encapsulated AAC into RTP payloads in accordance with RFC3640
  """

  use Bunch
  require Membrane.Logger

  @typedoc """
    Bitrate mode
    Supported modes are low bitrate and high bitrate, with the main difference being the limits they impose on access unit size.
    For more details see validate_max_au_size/2 and bitrate_params/1 defined in this module.
  """
  @type mode() :: :lbr | :hbr

  @doc """
    Utility function that constructs an AU header section for a payload with the corresponding AU sizes.
    From the RFC:
      +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+- .. -+-+-+-+-+-+-+-+-+-+
      |AU-headers-length|AU-header|AU-header|      |AU-header|padding|
      |                 |   (1)   |   (2)   |      |   (n)   | bits  |
      +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+- .. -+-+-+-+-+-+-+-+-+-+
    It is important to note that for AAC each individual header is octet aligned, and so padding is not needed.
    The AU-headers-length is measured in bits, and for AAC defined to be coded using 16 bits.
    A single header consists of the size of the corresponding frame measured in bytes,
    followed by an AU-index for the first frame in the payload, and an AU-index-delta otherwise.
    The AU-index MUST be 0. The delta values need not be 0 in general unless one assumes no interleaving, as is done here.
  """
  @spec make_headers([pos_integer()], mode()) :: binary()
  def make_headers(sizes, mode) do
    aus_count = length(sizes)
    {au_size_length, au_index_length} = bitrate_params(mode)
    header_length = au_size_length + au_index_length

    headers_length =
      aus_count * header_length

    au_index_deltas = List.duplicate(0, aus_count)

    headers =
      Enum.zip_with(sizes, au_index_deltas, fn au_size, au_index ->
        <<au_size::size(au_size_length), au_index::size(au_index_length)>>
      end)
      |> :binary.list_to_bin()

    <<headers_length::16>> <> headers
  end

  @doc """
    Parses an RTP payload by first parsing the header section and then the frames themselves.
    For more information about the header size, see make_headers/2 from this module.
    From the RFC:
         +---------+-----------+-----------+---------------+
         | RTP     | AU Header | Auxiliary | Access Unit   |
         | Header  | Section   | Section   | Data Section  |
         +---------+-----------+-----------+---------------+

                   <----------RTP Packet Payload----------->
    For AAC the auxiliary section must always be empty.
  """
  @spec parse_packet(binary(), any()) :: {:ok, [binary()]} | {:error, any()}
  def parse_packet(packet, mode) do
    case packet do
      <<headers_length::16, header_section::bits-size(headers_length), au_data_section::binary>> ->
        parse_sections(header_section, au_data_section, mode)

      # payload shorter than 2 bytes, AU-headers-length pointing past the end of the
      # payload or AU header section that is not octet aligned
      _malformed ->
        {:error, {"Malformed packet:", packet}}
    end
  end

  defp parse_sections(header_section, au_data_section, mode) do
    {au_size_length, au_index_length} = bitrate_params(mode)

    headers =
      for <<au_size::size(^au_size_length), au_index::size(^au_index_length) <- header_section>>,
        do: {au_size, au_index}

    {au_sizes, au_indices} = headers |> Enum.unzip()

    with true <-
           validate_sizes(au_sizes, au_data_section)
           ~>> (false -> {:inconsistent_sizes, au_sizes, au_data_section}) do
      _warning =
        if not validate_deltas(au_indices) do
          Membrane.Logger.warning(
            "Access unit deltas indicate access units are interleaved, but the depayloader does not support it."
          )
        end

      parse_data_section(au_sizes, au_data_section)
    else
      reason -> {:error, {"Validation failed:", reason}}
    end
  end

  @spec parse_data_section([pos_integer()], binary()) :: {:ok, [binary()]} | {:error, any()}
  defp parse_data_section(au_sizes, au_data_section) do
    result =
      Bunch.Enum.try_map_reduce(au_sizes, au_data_section, fn len, data ->
        case data do
          <<au::binary-size(^len), rest::binary>> -> {{:ok, au}, rest}
          _else -> {{:error, "Couldn't consume remaining data"}, data}
        end
      end)

    case result do
      {{:ok, aus}, <<>>} ->
        {:ok, aus}

      {{:error, reason}, data} ->
        {:error, {reason, data}}

      {{:ok, aus}, data} ->
        {:error, {"Parsing succeeded but did not consume remaining data", aus, data}}
    end
  end

  @spec validate_max_au_size(mode(), binary()) :: boolean()
  def validate_max_au_size(mode, au) do
    import Bitwise

    {size_length, _index_length} = bitrate_params(mode)
    max_au_size = (1 <<< size_length) - 1
    byte_size(au) <= max_au_size
  end

  @spec validate_deltas([integer()]) :: boolean()
  defp validate_deltas(au_indices),
    do: au_indices == List.duplicate(0, length(au_indices))

  @spec validate_sizes([pos_integer()], binary()) :: boolean()
  defp validate_sizes(au_sizes, au_data_section),
    do: Enum.sum(au_sizes) == byte_size(au_data_section)

  @spec bitrate_params(mode()) ::
          {au_size_length :: pos_integer(), au_index_length :: pos_integer()}
  defp bitrate_params(:lbr), do: {6, 2}
  defp bitrate_params(:hbr), do: {13, 3}
end
