defmodule PaperForge.Security do
  @moduledoc """
  PDF AES-256 encryption and document permission policy.

  Passwords and derived keys exist only for the duration of serialization and
  are never stored in `PaperForge.Document`.
  """

  import Bitwise

  alias PaperForge.Object
  alias PaperForge.Serializer
  alias PaperForge.Stream

  defstruct [:file_key, :file_id, :object_id, :dictionary, :random, :encrypt_metadata]

  @type t :: %__MODULE__{
          file_key: binary(),
          file_id: binary(),
          object_id: pos_integer(),
          dictionary: map(),
          random: (pos_integer() -> binary()),
          encrypt_metadata: boolean()
        }

  @spec prepare([Object.t()], keyword()) :: {:ok, t(), Object.t()} | {:error, term()}
  def prepare(objects, options) do
    with :aes_256 <- Keyword.get(options, :algorithm, :aes_256),
         {:ok, user_password} <- password(options, :user_password, ""),
         {:ok, owner_password} <- password(options, :owner_password, nil) do
      random = Keyword.get(options, :random, &:crypto.strong_rand_bytes/1)
      file_key = random.(32)
      file_id = Keyword.get_lazy(options, :file_id, fn -> random.(16) end)
      permissions = permission_value(Keyword.get(options, :permissions, []))
      encrypt_metadata = Keyword.get(options, :encrypt_metadata, true)

      user_validation_salt = random.(8)
      user_key_salt = random.(8)
      owner_validation_salt = random.(8)
      owner_key_salt = random.(8)

      u_hash = hardened_hash(user_password, user_validation_salt, "")
      u = u_hash <> user_validation_salt <> user_key_salt
      ue_key = hardened_hash(user_password, user_key_salt, "")
      ue = aes_cbc_no_padding(file_key, ue_key, <<0::128>>)

      o_hash = hardened_hash(owner_password, owner_validation_salt, u)
      o = o_hash <> owner_validation_salt <> owner_key_salt
      oe_key = hardened_hash(owner_password, owner_key_salt, u)
      oe = aes_cbc_no_padding(file_key, oe_key, <<0::128>>)

      perms = encrypted_permissions(file_key, permissions, encrypt_metadata, random)
      object_id = maximum_object_id(objects) + 1

      dictionary = %{
        "Filter" => {:name, "Standard"},
        "V" => 5,
        "Length" => 256,
        "R" => 6,
        "O" => {:hex_string, o},
        "U" => {:hex_string, u},
        "OE" => {:hex_string, oe},
        "UE" => {:hex_string, ue},
        "P" => permissions,
        "Perms" => {:hex_string, perms},
        "EncryptMetadata" => encrypt_metadata,
        "CF" => %{
          "StdCF" => %{
            "AuthEvent" => {:name, "DocOpen"},
            "CFM" => {:name, "AESV3"},
            "Length" => 32
          }
        },
        "StmF" => {:name, "StdCF"},
        "StrF" => {:name, "StdCF"}
      }

      context = %__MODULE__{
        file_key: file_key,
        file_id: file_id,
        object_id: object_id,
        dictionary: dictionary,
        random: random,
        encrypt_metadata: encrypt_metadata
      }

      {:ok, context, Object.new(object_id, dictionary)}
    else
      {:error, _reason} = error -> error
      algorithm when algorithm != :aes_256 -> {:error, {:unsupported_algorithm, algorithm}}
    end
  end

  @spec encrypt_object(term(), t()) :: term()
  def encrypt_object(value, context), do: encrypt_value(value, context)

  defp encrypt_value(
         %Stream{dictionary: %{"Type" => {:name, "Metadata"}}} = stream,
         %__MODULE__{encrypt_metadata: false}
       ) do
    {dictionary, encoded_data} = Serializer.prepare_stream(stream)
    %Stream{dictionary: dictionary, data: encoded_data, filters: []}
  end

  defp encrypt_value(%Stream{} = stream, context) do
    {dictionary, encoded_data} = Serializer.prepare_stream(stream)
    encrypted_data = encrypt_binary(encoded_data, context)

    %Stream{
      dictionary: encrypt_value(dictionary, context),
      data: encrypted_data,
      filters: []
    }
  end

  defp encrypt_value({:hex_string, value}, context) when is_binary(value),
    do: {:hex_string, encrypt_binary(value, context)}

  defp encrypt_value({:name, _value} = name, _context), do: name
  defp encrypt_value(%PaperForge.Reference{} = reference, _context), do: reference

  defp encrypt_value(value, context) when is_binary(value),
    do: {:hex_string, encrypt_binary(value, context)}

  defp encrypt_value(value, context) when is_list(value),
    do: Enum.map(value, &encrypt_value(&1, context))

  defp encrypt_value(value, context) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, encrypt_value(item, context)} end)

  defp encrypt_value(value, _context), do: value

  defp encrypt_binary(value, context) do
    iv = context.random.(16)
    iv <> :crypto.crypto_one_time(:aes_256_cbc, context.file_key, iv, pad(value, 16), true)
  end

  defp hardened_hash(password, salt, user_key) do
    initial = :crypto.hash(:sha256, password <> salt <> user_key)
    harden(password, initial, user_key, 0, 0)
  end

  defp harden(_password, key, _user_key, iteration, last)
       when iteration >= 64 and last <= iteration - 32,
       do: binary_part(key, 0, 32)

  defp harden(password, key, user_key, iteration, _last) do
    block = :binary.copy(password <> key <> user_key, 64)
    aes_key = binary_part(key, 0, 16)
    iv = binary_part(key, 16, 16)
    encrypted = :crypto.crypto_one_time(:aes_128_cbc, aes_key, iv, block, true)
    selector = encrypted |> binary_part(0, 16) |> :binary.decode_unsigned() |> rem(3)

    digest =
      case selector do
        0 -> :crypto.hash(:sha256, encrypted)
        1 -> :crypto.hash(:sha384, encrypted)
        2 -> :crypto.hash(:sha512, encrypted)
      end

    last = :binary.last(encrypted)
    harden(password, digest, user_key, iteration + 1, last)
  end

  defp encrypted_permissions(file_key, permissions, encrypt_metadata, random) do
    plain =
      <<permissions::signed-little-32, 0xFFFFFFFF::little-32,
        if(encrypt_metadata, do: ?T, else: ?F), "adb", random.(4)::binary>>

    :crypto.crypto_one_time(:aes_256_ecb, file_key, plain, true)
  end

  defp permission_value(options) do
    unsigned = 0xFFFFF0C0

    unsigned =
      set_permission(
        unsigned,
        3,
        Keyword.get(options, :print) in [:low_resolution, :high_resolution]
      )

    unsigned = set_permission(unsigned, 12, Keyword.get(options, :print) == :high_resolution)
    unsigned = set_permission(unsigned, 5, Keyword.get(options, :copy, false))

    unsigned =
      set_permission(
        unsigned,
        10,
        Keyword.get(options, :extract, Keyword.get(options, :copy, false))
      )

    unsigned =
      if Keyword.get(options, :modify, false) do
        Enum.reduce([4, 6, 9, 11], unsigned, &set_permission(&2, &1, true))
      else
        unsigned
      end

    if unsigned >= 0x80000000, do: unsigned - 0x1_0000_0000, else: unsigned
  end

  defp set_permission(value, bit, true), do: bor(value, 1 <<< (bit - 1))
  defp set_permission(value, _bit, false), do: value

  defp password(options, key, default) do
    case Keyword.get(options, key, default) do
      nil -> {:error, {:missing_password, key}}
      value when is_binary(value) and byte_size(value) <= 127 -> {:ok, value}
      value when is_binary(value) -> {:error, {:password_too_long, key}}
      _ -> {:error, {:invalid_password, key}}
    end
  end

  defp aes_cbc_no_padding(value, key, iv),
    do: :crypto.crypto_one_time(:aes_256_cbc, key, iv, value, true)

  defp pad(value, block_size) do
    padding = block_size - rem(byte_size(value), block_size)
    value <> :binary.copy(<<padding>>, padding)
  end

  defp maximum_object_id([]), do: 0
  defp maximum_object_id(objects), do: objects |> Enum.map(& &1.id) |> Enum.max()
end
