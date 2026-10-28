defmodule PaperForge.PDF.DecryptionTest do
  use ExUnit.Case, async: true
  alias PaperForge.PDF.Decryption
  alias PaperForge.{Security, Stream}

  test "authenticates user and owner passwords and decrypts strings and streams" do
    {:ok, context, object} =
      Security.prepare([],
        user_password: "reader",
        owner_password: "owner",
        permissions: [copy: true]
      )

    for password <- ["reader", "owner"] do
      decoder = Decryption.authenticate(object.value, %{}, password)
      value = %{"Text" => "Contract", "Data" => Stream.new("payload"), "Name" => {:name, "Test"}}
      encrypted = Security.encrypt_object(value, context)

      assert %{
               "Text" => {:hex_string, "Contract"},
               "Data" => %Stream{data: "payload"},
               "Name" => {:name, "Test"}
             } = Decryption.decrypt(encrypted, decoder)

      assert decoder.permissions == object.value["P"]
    end

    assert {:pdf_error, :password_required} =
             catch_throw(Decryption.authenticate(object.value, %{}, nil))

    assert {:pdf_error, :invalid_password} =
             catch_throw(Decryption.authenticate(object.value, %{}, "wrong"))
  end

  test "signature Contents remains unencrypted while other signature strings decrypt" do
    {:ok, context, object} =
      Security.prepare([], user_password: "reader", owner_password: "owner")

    decoder = Decryption.authenticate(object.value, %{}, "reader")
    reason = Security.encrypt_object("Approved", context)

    signature = %{
      "Type" => {:name, "Sig"},
      "Contents" => {:hex_string, <<1, 2, 3>>},
      "Reason" => reason
    }

    assert %{"Contents" => {:hex_string, <<1, 2, 3>>}, "Reason" => {:hex_string, "Approved"}} =
             Decryption.decrypt(signature, decoder)
  end

  test "rejects tampered permissions and unsupported crypt filters" do
    {:ok, _, object} = Security.prepare([], user_password: "", owner_password: "owner")

    assert {:pdf_error, :invalid_encrypted_permissions} =
             catch_throw(Decryption.authenticate(Map.put(object.value, "P", 0), %{}, ""))

    assert {:pdf_error, :unsupported_crypt_filter} =
             catch_throw(
               Decryption.authenticate(Map.put(object.value, "StmF", {:name, "Unknown"}), %{}, "")
             )
  end
end
