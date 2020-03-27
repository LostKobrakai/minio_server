if Code.ensure_loaded?(ExAws.Operation.S3) do
  defmodule MinioServer.S3Api do
    @moduledoc """
    Implementation of aws livecycle configuration.

    This is currently missing in `:ex_aws_s3`, but there's a [PR](https://github.com/ex-aws/ex_aws_s3/pull/87).
    """

    @doc """
    Update or create a bucket lifecycle configuration

    ## Live-Cycle Rule Format

        %{
          # Unique id for the rule (max. 255 chars, max. 1000 rules allowed)
          id: "123",

          # Disabled rules are not executed
          enabled: true,

          # Filters
          # Can be based on prefix, object tag(s), both or none
          filter: %{
            prefix: "prefix/",
            tags: %{
              "key" => "value"
            }
          },

          # Actions
          # https://docs.aws.amazon.com/AmazonS3/latest/dev/intro-lifecycle-rules.html#intro-lifecycle-rules-actions
          actions: %{
            transition: %{
              trigger: {:date, ~D[2020-03-26]}, # Date or days based
              storage: ""
            },
            expiration: %{
              trigger: {:days, 2}, # Date or days based
              expired_object_delete_marker: true
            },
            noncurrent_version_transition: %{
              trigger: {:days, 2}, # Only days based
              storage: ""
            },
            noncurrent_version_expiration: %{
              trigger: {:days, 2} # Only days based
            },
            abort_incomplete_multipart_upload: %{
              trigger: {:days, 2} # Only days based
            }
          }
        }

    """
    @spec put_bucket_lifecycle(bucket :: binary, lifecycle_rules :: list(map())) ::
            ExAws.Operation.S3.t()
    def put_bucket_lifecycle(bucket, lifecycle_rules) do
      rules =
        lifecycle_rules
        |> Enum.map(&build_lifecycle_rule/1)
        |> IO.iodata_to_binary()

      body = "<LifecycleConfiguration>#{rules}</LifecycleConfiguration>"

      content_md5 = :crypto.hash(:md5, body) |> Base.encode64()
      headers = %{"content-md5" => content_md5}

      request(:put, bucket, "/", resource: "lifecycle", body: body, headers: headers)
    end

    defp build_lifecycle_rule(rule) do
      # ID
      properties = ["<ID>", rule.id, "</ID>"]

      # Status
      status_text = if rule.enabled, do: "Enabled", else: "Disabled"
      properties = [["<Status>", status_text, "</Status>"] | properties]

      # Filter
      filter_prefix =
        case Map.get(rule.filter, :prefix, nil) do
          prefix when is_binary(prefix) and prefix != "" ->
            [["<Prefix>", prefix, "</Prefix>"]]

          _ ->
            []
        end

      filter_tags =
        Enum.map(Map.get(rule.filter, :tags, []), fn {key, value} ->
          ["<Tag>", ["<Key>", key, "</Key>", "<Value>", value, "</Value>"], "</Tag>"]
        end)

      filters =
        case filter_prefix ++ filter_tags do
          [] -> []
          [_] = filters -> filters
          many -> ["<And>", many, "</And>"]
        end

      properties = [["<Filter>", filters, "</Filter>"] | properties]

      # Actions
      mapping = [
        transition: %{
          tag: "Transition",
          action_tags: fn %{storage: storage} ->
            [["<StorageClass>", storage, "</StorageClass>"]]
          end
        },
        expiration: %{
          tag: "Expiration",
          action_tags: fn %{expired_object_delete_marker: marker} ->
            marker = if marker, do: "true", else: "false"
            [["<ExpiredObjectDeleteMarker>", marker, "</ExpiredObjectDeleteMarker>"]]
          end
        },
        noncurrent_version_transition: %{
          tag: "NoncurrentVersionTransition",
          action_tags: fn %{storage: storage} ->
            [["<StorageClass>", storage, "</StorageClass>"]]
          end
        },
        noncurrent_version_expiration: %{
          tag: "NoncurrentVersionExpiration",
          action_tags: fn _data -> [] end
        },
        abort_incomplete_multipart_upload: %{
          tag: "AbortIncompleteMultipartUpload",
          action_tags: fn _data -> [] end
        }
      ]

      properties =
        Enum.reduce(mapping, properties, fn {key, %{tag: tag, action_tags: fun}}, properties ->
          case rule.actions[key] do
            %{trigger: trigger} = config ->
              trigger = trigger(key, trigger)
              action_tags = fun.(config)
              [["<#{tag}>", [trigger | action_tags], "</#{tag}>"] | properties]

            _ ->
              properties
          end
        end)

      ["<Rule>", properties, "</Rule>"]
      |> IO.iodata_to_binary()
    end

    defp trigger(action, {:date, %Date{} = date}) when action in [:transition, :expiration] do
      ["<Date>", Date.to_iso8601(date), "</Date>"]
    end

    defp trigger(action, {:days, days})
         when action in [:transition, :expiration] and is_integer(days) and days > 0 do
      ["<Days>", Integer.to_string(days), "</Days>"]
    end

    defp trigger(action, {:days, days})
         when action in [:abort_incomplete_multipart_upload] and is_integer(days) and days > 0 do
      ["<DaysAfterInitiation>", Integer.to_string(days), "</DaysAfterInitiation>"]
    end

    defp trigger(action, {:days, days})
         when action in [:noncurrent_version_transition, :noncurrent_version_expiration] and
                is_integer(days) and days > 0 do
      ["<NoncurrentDays>", Integer.to_string(days), "</NoncurrentDays>"]
    end

    defp request(http_method, bucket, path, data, opts \\ %{}) do
      %ExAws.Operation.S3{
        http_method: http_method,
        bucket: bucket,
        path: path,
        body: data[:body] || "",
        headers: data[:headers] || %{},
        resource: data[:resource] || "",
        params: data[:params] || %{}
      }
      |> struct(opts)
    end
  end
end
