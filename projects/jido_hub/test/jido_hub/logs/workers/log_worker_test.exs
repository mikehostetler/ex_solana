defmodule JidoHub.Logs.Workers.LogWorkerTest do
  use JidoHub.DataCase, async: true
  use Oban.Testing, repo: JidoHub.Repo

  import JidoHub.Fixtures

  alias JidoHub.Logs.Workers.LogWorker

  describe "perform/1" do
    test "successfully creates a log entry" do
      user = create_test_user()

      attrs = %{
        "action" => "user.login",
        "user_id" => user.id,
        "metadata" => %{"ip" => "127.0.0.1"}
      }

      opts = []

      assert {:ok, log} =
               perform_job(LogWorker, %{attrs: attrs, opts: opts})

      assert log.action == "user.login"
      assert log.user_id == user.id
      assert log.metadata == %{"ip" => "127.0.0.1"}
    end

    test "creates log with user information" do
      user = create_test_user()

      attrs = %{
        "action" => "user.update",
        "user_id" => user.id
      }

      opts = []

      assert {:ok, log} =
               perform_job(LogWorker, %{attrs: attrs, opts: opts})

      assert log.action == "user.update"
      assert log.user_id == user.id
      assert log.user_type == "user"
    end

    test "creates system log when no user provided" do
      attrs = %{
        "action" => "system.startup",
        "metadata" => %{"version" => "1.0.0"}
      }

      opts = []

      assert {:ok, log} =
               perform_job(LogWorker, %{attrs: attrs, opts: opts})

      assert log.action == "system.startup"
      assert log.user_type == "system"
      assert is_nil(log.user_id)
    end
  end

  describe "log_async/2" do
    test "enqueues a job to create a log entry" do
      user = create_test_user()

      attrs = %{
        action: "user.logout",
        user_id: user.id
      }

      assert {:ok, %Oban.Job{}} = JidoHub.Logs.log_async(attrs)

      assert_enqueued worker: LogWorker, queue: :logs
    end

    test "enqueues job with correct arguments" do
      user = create_test_user()

      attrs = %{
        action: "user.created",
        user_id: user.id,
        metadata: %{source: "api"}
      }

      assert {:ok, job} = JidoHub.Logs.log_async(attrs, [])

      assert_enqueued worker: LogWorker,
                      queue: :logs,
                      args: %{
                        attrs: %{
                          action: "user.created",
                          user_id: user.id,
                          metadata: %{source: "api"}
                        },
                        opts: []
                      }

      assert job.queue == "logs"
      assert job.max_attempts == 3
    end

    test "job can be processed successfully" do
      attrs = %{
        action: "test.action"
      }

      {:ok, _job} = JidoHub.Logs.log_async(attrs)

      assert [%Oban.Job{state: "available"}] = all_enqueued(worker: LogWorker)

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :logs)

      query = Ash.Query.for_read(JidoHub.Logs.Log, :read)
      assert {:ok, [log]} = Ash.read(query, authorize?: false)
      assert log.action == "test.action"
    end
  end

  describe "retry behavior" do
    test "worker is configured with max_attempts of 3" do
      assert LogWorker.__opts__()[:max_attempts] == 3
    end

    test "worker is configured for logs queue" do
      assert LogWorker.__opts__()[:queue] == :logs
    end
  end

  defp create_test_user do
    create_user!()
  end
end
