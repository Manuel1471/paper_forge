defmodule PaperForge.PDF.Decryption do
  @moduledoc false
  alias PaperForge.PDF.Syntax
  alias PaperForge.{Reference, Security, Stream}

  def authenticate(_, _, nil), do: Syntax.fail(:password_required)

  def authenticate(dictionary, _trailer, password) when is_binary(password) do
    validate_handler(dictionary)
    password = binary_part(password, 0, min(byte_size(password), 127))
    user = bytes(dictionary["U"])
    owner = bytes(dictionary["O"])

    unless byte_size(user) == 48 and byte_size(owner) == 48,
      do: Syntax.fail(:invalid_encryption_dictionary)

    revision = dictionary["R"]

    {key, authentication} =
      cond do
        valid_password?(password, owner, user, revision) ->
          {unwrap(password, owner, user, bytes(dictionary["OE"]), revision), :owner}

        valid_password?(password, user, "", revision) ->
          {unwrap(password, user, "", bytes(dictionary["UE"]), revision), :user}

        true ->
          Syntax.fail(:invalid_password)
      end

    permissions = dictionary["P"]
    encrypt_metadata = Map.get(dictionary, "EncryptMetadata", true)
    verify_permissions(key, bytes(dictionary["Perms"]), permissions, encrypt_metadata)

    %{
      key: key,
      revision: revision,
      permissions: permissions,
      encrypt_metadata: encrypt_metadata,
      authentication: authentication,
      streams: dictionary["StmF"] != {:name, "Identity"},
      strings: dictionary["StrF"] != {:name, "Identity"}
    }
  end

  def authenticate(_, _, _), do: Syntax.fail(:invalid_password)

  defp validate_handler(dictionary) do
    unless dictionary["Filter"] == {:name, "Standard"} and dictionary["V"] == 5 and
             dictionary["R"] in [5, 6],
           do: Syntax.fail({:unsupported_encryption, Map.take(dictionary, ["Filter", "V", "R"])})

    Enum.each(["StmF", "StrF"], fn field ->
      name = dictionary[field]

      unless name == {:name, "Identity"} or valid_filter?(dictionary, name),
        do: Syntax.fail(:unsupported_crypt_filter)
    end)

    if dictionary["EFF"] && dictionary["EFF"] != dictionary["StmF"],
      do: Syntax.fail(:unsupported_embedded_file_crypt_filter)
  end

  defp valid_filter?(dictionary, {:name, name}),
    do: get_in(dictionary, ["CF", name, "CFM"]) == {:name, "AESV3"}

  defp valid_filter?(_, _), do: false
  defp bytes({:hex_string, data}) when is_binary(data), do: data
  defp bytes(data) when is_binary(data), do: data
  defp bytes(_), do: Syntax.fail(:invalid_encryption_dictionary)

  defp hash(password, salt, user, 5), do: :crypto.hash(:sha256, password <> salt <> user)
  defp hash(password, salt, user, 6), do: Security.password_hash(password, salt, user)

  defp valid_password?(password, entry, user, revision) do
    <<expected::binary-size(32), salt::binary-size(8), _::binary>> = entry
    :crypto.hash_equals(expected, hash(password, salt, user, revision))
  end

  defp unwrap(password, entry, user, wrapped, revision) do
    unless byte_size(wrapped) == 32, do: Syntax.fail(:invalid_encryption_dictionary)
    salt = binary_part(entry, 40, 8)
    key = hash(password, salt, user, revision)
    :crypto.crypto_one_time(:aes_256_cbc, key, <<0::128>>, wrapped, false)
  end

  defp verify_permissions(key, perms, expected, metadata) when byte_size(perms) == 16 do
    case :crypto.crypto_one_time(:aes_256_ecb, key, perms, false) do
      <<^expected::signed-little-32, 0xFFFFFFFF::little-32, flag, "adb", _::binary-size(4)>>
      when flag in [?T, ?F] ->
        if flag == ?T != metadata, do: Syntax.fail(:invalid_encrypted_permissions)

      _ ->
        Syntax.fail(:invalid_encrypted_permissions)
    end
  end

  defp verify_permissions(_, _, _, _), do: Syntax.fail(:invalid_encrypted_permissions)

  def decrypt(%Reference{} = reference, _), do: reference
  def decrypt({:name, _} = name, _), do: name

  def decrypt(%Stream{} = stream, context) do
    metadata = stream.dictionary["Type"] == {:name, "Metadata"}

    data =
      if context.streams and (not metadata or context.encrypt_metadata),
        do: decrypt_binary(stream.data, context.key),
        else: stream.data

    %{stream | data: data, dictionary: decrypt(stream.dictionary, context)}
  end

  def decrypt({:hex_string, data}, %{strings: true} = context),
    do: {:hex_string, decrypt_binary(data, context.key)}

  def decrypt(value, %{strings: true} = context) when is_binary(value),
    do: decrypt_binary(value, context.key)

  # Signature Contents is excluded from document encryption by the PDF format.
  def decrypt(%{"Type" => {:name, "Sig"}} = value, context), do: decrypt_signature(value, context)

  def decrypt(%{"ByteRange" => _, "Contents" => _} = value, context),
    do: decrypt_signature(value, context)

  def decrypt(value, context) when is_map(value),
    do: Map.new(value, fn {key, val} -> {key, decrypt(val, context)} end)

  def decrypt(value, context) when is_list(value), do: Enum.map(value, &decrypt(&1, context))
  def decrypt(value, _), do: value

  defp decrypt_signature(value, context) do
    Map.new(value, fn
      {"Contents", contents} -> {"Contents", contents}
      {key, item} -> {key, decrypt(item, context)}
    end)
  end

  defp decrypt_binary(<<iv::binary-size(16), encrypted::binary>>, key)
       when byte_size(encrypted) > 0 and rem(byte_size(encrypted), 16) == 0 do
    plain = :crypto.crypto_one_time(:aes_256_cbc, key, iv, encrypted, false)
    n = :binary.last(plain)

    unless n in 1..16 and binary_part(plain, byte_size(plain) - n, n) == :binary.copy(<<n>>, n),
      do: Syntax.fail(:invalid_encrypted_stream)

    binary_part(plain, 0, byte_size(plain) - n)
  end

  defp decrypt_binary(_, _), do: Syntax.fail(:invalid_encrypted_stream)
end
