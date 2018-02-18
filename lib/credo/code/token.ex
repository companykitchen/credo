defmodule Credo.Code.Token do
  @moduledoc """
  This module provides helper functions to analyse tokens.
  """

  @doc """
  Returns `true` if the given `token` contains a line break.
  """
  def eol?(token)

  def eol?(list) when is_list(list) do
    Enum.any?(list, &eol?/1)
  end

  def eol?({_, {_, _, _}, _, list, _, _}) when is_list(list) do
    Enum.any?(list, &eol?/1)
  end

  def eol?({_, {_, _, _}, list}) when is_list(list) do
    Enum.any?(list, &eol?/1)
  end

  def eol?({{_, _, _}, list}) when is_list(list) do
    Enum.any?(list, &eol?/1)
  end

  def eol?({:eol, {_, _, _}}), do: true
  def eol?(_), do: false

  @doc """
  Returns the position of a token in the form

      {line_no_start, col_start, line_no_end, col_end}
  """
  def position(token)

  if Version.match?(System.version(), ">= 1.6.0-rc") do
    # Elixir >= 1.6.0
    defdelegate position(token), to: __MODULE__.PositionHelper
  else
    # Elixir <= 1.5.x
    defdelegate position(token), to: __MODULE__.ElixirPre1_6_0
  end

  defmodule PositionHelper do
    @moduledoc false

    @doc false
    def position({_, {line_no, col_start, _}, atom_or_charlist, _, _, _}) do
      position_tuple(atom_or_charlist, line_no, col_start)
    end

    def position({_, {line_no, col_start, _}, atom_or_charlist, _, _}) do
      position_tuple(atom_or_charlist, line_no, col_start)
    end

    def position({_, {line_no, col_start, _}, atom_or_charlist, _}) do
      position_tuple(atom_or_charlist, line_no, col_start)
    end

    def position({:bin_string, {line_no, col_start, _}, atom_or_charlist}) do
      position_tuple_for_quoted_string(atom_or_charlist, line_no, col_start)
    end

    def position({:bin_heredoc, {line_no, col_start, _}, atom_or_charlist}) do
      position_tuple_for_heredoc(atom_or_charlist, line_no, col_start)
    end

    def position({:atom_unsafe, {line_no, col_start, _}, atom_or_charlist}) do
      position_tuple_for_quoted_string(atom_or_charlist, line_no, col_start)
    end

    def position({_, {line_no, col_start, _}, atom_or_charlist}) do
      position_tuple(atom_or_charlist, line_no, col_start)
    end

    def position({atom_or_charlist, {line_no, col_start, _}}) do
      position_tuple(atom_or_charlist, line_no, col_start)
    end

    # interpolation
    def position({{line_no, col_start, _}, list}) when is_list(list) do
      {line_no, col_start, line_no_end, col_end} =
        position_tuple_for_quoted_string(list, line_no, col_start)

      {line_no, col_start, line_no_end, col_end}
    end

    #

    defp position_tuple(list, line_no, col_start) when is_list(list) do
      binary = to_string(list)
      col_end = col_start + String.length(binary)

      {line_no, col_start, line_no, col_end}
    end

    defp position_tuple(atom, line_no, col_start) when is_atom(atom) do
      binary = to_string(atom)
      col_end = col_start + String.length(binary)

      {line_no, col_start, line_no, col_end}
    end

    defp position_tuple(number, line_no, col_start) when is_number(number) do
      binary = to_string([number])
      col_end = col_start + String.length(binary)

      {line_no, col_start, line_no, col_end}
    end

    defp position_tuple(_, _line_no, _col_start), do: nil

    defp position_tuple_for_heredoc(list, line_no, col_start)
         when is_list(list) do
      # add 3 for """ (closing double quote)
      {line_no_end, col_end, _terminator} = convert_to_col_end(line_no, col_start, list)

      col_end = col_end + 3

      {line_no, col_start, line_no_end, col_end}
    end

    @doc false
    def position_tuple_for_quoted_string(list, line_no, col_start)
        when is_list(list) do
      # add 1 for " (closing double quote)
      {line_no_end, col_end, terminator} = convert_to_col_end(line_no, col_start, list)

      {line_no_end, col_end} =
        case terminator do
          :eol ->
            # move to next line
            {line_no_end + 1, 1}

          _ ->
            # add 1 for " (closing double quote)
            {line_no_end, col_end + 1}
        end

      {line_no, col_start, line_no_end, col_end}
    end

    #

    defp convert_to_col_end(line_no, col_start, list) when is_list(list) do
      Enum.reduce(list, {line_no, col_start, nil}, &reduce_to_col_end/2)
    end

    # {{1, 25, 32}, [{:identifier, {1, 27, 31}, :name}]}
    defp convert_to_col_end(_, _, {{line_no, col_start, _}, list}) do
      {line_no_end, col_end, _terminator} = convert_to_col_end(line_no, col_start, list)

      # add 1 for } (closing parens of interpolation)
      col_end = col_end + 1

      {line_no_end, col_end, :interpolation}
    end

    defp convert_to_col_end(_, _, {:eol, {line_no, col_start, _}}) do
      {line_no, col_start, :eol}
    end

    defp convert_to_col_end(_, _, {value, {line_no, col_start, _}}) do
      {line_no, to_col_end(col_start, value), nil}
    end

    defp convert_to_col_end(_, _, {:bin_string, {line_no, col_start, nil}, list})
         when is_list(list) do
      # add 2 for opening and closing "
      {line_no, col_end, terminator} =
        Enum.reduce(list, {line_no, col_start, nil}, &reduce_to_col_end/2)

      {line_no, col_end + 2, terminator}
    end

    defp convert_to_col_end(_, _, {:bin_string, {line_no, col_start, nil}, value}) do
      # add 2 for opening and closing "
      {line_no, to_col_end(col_start, value, 2), :bin_string}
    end

    defp convert_to_col_end(_, _, {:list_string, {line_no, col_start, nil}, value}) do
      # add 2 for opening and closing '
      {line_no, to_col_end(col_start, value, 2), :bin_string}
    end

    defp convert_to_col_end(_, _, {_, {line_no, col_start, nil}, list})
         when is_list(list) do
      Enum.reduce(list, {line_no, col_start, nil}, &reduce_to_col_end/2)
    end

    defp convert_to_col_end(_, _, {_, {line_no, col_start, nil}, value}) do
      {line_no, to_col_end(col_start, value), nil}
    end

    defp convert_to_col_end(_, _, {_, {line_no, col_start, _value}, value}) do
      {line_no, to_col_end(col_start, value), nil}
    end

    defp convert_to_col_end(_, _, {:sigil, {line_no, col_start, nil}, _, value, _, _}) do
      {line_no, to_col_end(col_start, value), nil}
    end

    defp convert_to_col_end(line_no, col_start, value) do
      {line_no, to_col_end(col_start, value), nil}
    end

    #

    defp reduce_to_col_end(value, {current_line_no, current_col_start, _}) do
      convert_to_col_end(current_line_no, current_col_start, value)
    end

    #

    def to_col_end(col_start, value, add \\ 0) do
      col_start + String.length(to_string(value)) + add
    end
  end

  defmodule ElixirPre1_6_0 do
    @moduledoc false

    alias Credo.Code.Token
    alias Credo.Code.Token.PositionHelper

    @doc false
    def position(token) do
      position(token, Token.eol?(token))
    end

    def position(token, true) do
      {line_no, col_start, col_end_pre_160} = do_position(token)

      {_line_no, _col_start, line_no_end, col_end} = PositionHelper.position(token)

      {line_no, col_start, line_no_end, max(col_end, col_end_pre_160)}
    end

    def position(token, false) do
      {line_no, col_start, col_end} = do_position(token)

      {line_no, col_start, line_no, col_end}
    end

    defp do_position({_, pos, _, _, _, _}), do: pos
    defp do_position({_, pos, _, _, _}), do: pos
    defp do_position({_, pos, _, _}), do: pos
    defp do_position({_, pos, _}), do: pos
    defp do_position({pos, list}) when is_list(list), do: pos
    defp do_position({atom, pos}) when is_atom(atom), do: pos
  end
end
