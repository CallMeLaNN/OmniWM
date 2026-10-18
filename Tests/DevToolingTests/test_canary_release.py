import importlib.util
import io
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("canary_release", SOURCE / "Scripts/canary_release.py")
canary_release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(canary_release)


def run(args, cwd=None):
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        raise AssertionError(f"{args} failed: {result.stderr}")
    return result


class GitRepo:
    def __init__(self, path):
        self.path = Path(path)

    def git(self, *args, date=None):
        env = dict(os.environ)
        if date:
            env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = date
        result = subprocess.run(
            ["git", "-C", str(self.path), *args],
            capture_output=True,
            text=True,
            env=env,
        )
        if result.returncode != 0:
            raise AssertionError(f"git {args} failed: {result.stderr}")
        return result.stdout.strip()

    def commit(self, message, date=None):
        self.git("commit", "--allow-empty", "-m", message, date=date)

    def tag(self, name, date=None):
        self.git("tag", name, date=date)

    def annotated_tag(self, name, date):
        self.git("tag", "-a", name, "-m", "release", date=date)


class CanaryReleaseTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.repo = GitRepo(tempfile.mkdtemp(dir=self._tmp.name))
        self.repo.git("init", "-q", "--initial-branch=main")
        self.repo.git("config", "user.name", "Test")
        self.repo.git("config", "user.email", "test@example.com")

    def seed_release(self):
        self.repo.commit("c1", date="2026-01-01T12:00:00+00:00")
        self.repo.tag("v0.7.5")

    def test_no_tags_builds(self):
        self.repo.commit("c1")
        self.assertEqual(canary_release.check(str(self.repo.path), False)["should_skip"], "false")

    def test_head_on_stable_or_canary_tag_skips(self):
        self.seed_release()
        with self.subTest(tag="v0.7.5"):
            result = canary_release.check(str(self.repo.path), False)
            self.assertEqual(result["should_skip"], "true")
            self.assertIn("v0.7.5", result["skip_reason"])
        self.repo.commit("c2")
        self.repo.commit("c3")
        self.repo.tag("canary-20261005-0400")
        with self.subTest(tag="canary-20261005-0400"):
            result = canary_release.check(str(self.repo.path), False)
            self.assertEqual(result["should_skip"], "true")
            self.assertIn("canary-20261005-0400", result["skip_reason"])

    def test_commit_after_stable_and_canary_tags_builds(self):
        self.seed_release()
        self.repo.commit("c2")
        with self.subTest(canary_pool="empty"):
            self.assertEqual(canary_release.check(str(self.repo.path), False)["should_skip"], "false")
        self.repo.tag("canary-20261004-0400")
        self.repo.commit("c3")
        with self.subTest(canary_pool="populated"):
            self.assertEqual(canary_release.check(str(self.repo.path), False)["should_skip"], "false")

    def test_force_overrides_skip(self):
        self.seed_release()
        self.assertEqual(canary_release.check(str(self.repo.path), True)["should_skip"], "false")

    def test_newest_tags_gate_independently(self):
        self.seed_release()
        self.repo.commit("c2")
        self.repo.tag("canary-20261004-0400")
        self.repo.commit("c3")
        self.repo.tag("v0.7.6")
        self.repo.commit("c4")
        self.assertEqual(canary_release.check(str(self.repo.path), False)["should_skip"], "false")
        self.repo.commit("c5")
        self.repo.tag("canary-20261005-0400")
        self.assertEqual(canary_release.check(str(self.repo.path), False)["should_skip"], "true")

    def test_annotated_release_tags_pick_newest_release_as_base(self):
        # Release tags are annotated, so committerdate is empty for them; the
        # base must fall back to the tagger date (creatordate), otherwise the
        # choice degrades to a lexicographic name comparison and picks
        # v0.7.9 over v0.7.10.
        self.repo.commit("c1")
        self.repo.annotated_tag("v0.7.9", date="2026-01-01T12:00:00")
        self.repo.commit("c2", date="2026-01-02T12:00:00")
        self.repo.annotated_tag("v0.7.10", date="2026-01-03T12:00:00")
        self.repo.commit("c3")
        text = canary_release.notes(str(self.repo.path))
        self.assertIn("Base tag: `v0.7.10`", text)

    def test_stable_release_after_canary_becomes_notes_base(self):
        self.seed_release()
        self.repo.commit("alpha", date="2026-01-02T12:00:00+00:00")
        self.repo.tag("canary-20261004-0400")
        self.repo.commit("release commit", date="2026-01-03T12:00:00+00:00")
        self.repo.annotated_tag("v0.7.6", date="2026-01-03T18:00:00+00:00")
        self.repo.commit("beta", date="2026-01-04T12:00:00+00:00")
        text = canary_release.notes(str(self.repo.path))
        # The canary tag predates the release that already covered "alpha",
        # so the notes must resume after v0.7.6 and repeat nothing.
        self.assertIn("Base tag: `v0.7.6`", text)
        self.assertIn("beta", text)
        self.assertNotIn(" alpha", text)

    def test_lightweight_tag_uses_commit_date_not_tag_creation_date(self):
        self.seed_release()
        self.repo.tag("canary-20261005-0400", date="2026-02-01T12:00:00+00:00")
        commit_date = int(self.repo.git("show", "-s", "--format=%ct", "HEAD"))
        self.assertEqual(
            canary_release.tags_with_create_dates(self.repo.path, canary_release.CANARY_GLOB),
            [(commit_date, "canary-20261005-0400")],
        )

    def test_canary_after_annotated_release_becomes_notes_base(self):
        self.repo.commit("released", date="2026-01-01T12:00:00+00:00")
        self.repo.annotated_tag("v0.7.5", date="2026-01-02T12:00:00+00:00")
        self.repo.commit("previous canary", date="2026-01-03T12:00:00+00:00")
        self.repo.tag("canary-20261004-0400")
        self.repo.commit("new feature", date="2026-01-04T12:00:00+00:00")
        text = canary_release.notes(self.repo.path)
        self.assertIn("Base tag: `canary-20261004-0400`", text)
        self.assertIn("new feature", text)
        self.assertNotIn("previous canary", text)
        self.assertNotIn("released", text)

    def test_diverged_tag_neither_skips_nor_becomes_notes_base(self):
        self.seed_release()
        self.repo.git("checkout", "-b", "other")
        self.repo.commit("other branch", date="2026-01-05T12:00:00+00:00")
        self.repo.annotated_tag("canary-20261005-0400", date="2026-01-06T12:00:00+00:00")
        self.repo.git("checkout", "main")
        self.repo.commit("main feature", date="2026-01-02T12:00:00+00:00")
        self.assertEqual(canary_release.check(self.repo.path, False)["should_skip"], "false")
        text = canary_release.notes(self.repo.path)
        self.assertIn("Base tag: `v0.7.5`", text)
        self.assertIn("main feature", text)
        self.assertNotIn("other branch", text)

    def test_head_before_released_commit_skips(self):
        self.seed_release()
        old_head = self.repo.git("rev-parse", "HEAD")
        self.repo.commit("already canaried", date="2026-01-02T12:00:00+00:00")
        self.repo.tag("canary-20261005-0400")
        self.repo.git("checkout", "--detach", old_head)
        result = canary_release.check(self.repo.path, False)
        self.assertEqual(result["should_skip"], "true")
        self.assertIn("canary-20261005-0400", result["skip_reason"])

    def test_notes_list_commits_since_previous_tag(self):
        self.seed_release()
        self.repo.commit("feature one", date="2026-10-18T11:55:08+00:00")
        self.repo.commit("feature two", date="2026-10-18T11:55:08+00:00")
        text = canary_release.notes(str(self.repo.path))
        self.assertIn("Base tag: `v0.7.5`", text)
        self.assertIn("### Changes since v0.7.5", text)
        self.assertIn("feature one", text)
        self.assertIn("feature two", text)
        self.assertNotRegex(text, r"(?m)^- [0-9a-f]+ c1$")

    def test_notes_without_any_tag_falls_back_to_recent_commits(self):
        self.repo.commit("first")
        text = canary_release.notes(str(self.repo.path))
        self.assertNotIn("Base tag", text)
        self.assertIn("Recent changes", text)
        self.assertIn("first", text)

    def test_notes_link_canary_guide_and_latest_stable_release(self):
        self.repo.commit("first")
        text = canary_release.notes(self.repo.path)
        self.assertIn("(https://omniwm.app/guides/install/#canary-builds)", text)
        self.assertIn("(https://github.com/OmniNull/OmniWM/releases/latest)", text)

    def test_non_commit_release_tag_fails_instead_of_looking_unreachable(self):
        self.seed_release()
        blob = self.repo.git("hash-object", "-w", str(SOURCE / "Scripts/canary_release.py"))
        self.repo.git("tag", "canary-invalid", blob)
        operations = (
            ("check", lambda: canary_release.check(self.repo.path, False)),
            ("notes", lambda: canary_release.notes(self.repo.path)),
        )
        for command, operation in operations:
            with self.subTest(command=command):
                with self.assertRaisesRegex(canary_release.CanaryError, "merge-base --is-ancestor .* failed"):
                    operation()

    def test_check_error_does_not_write_a_build_decision(self):
        self.seed_release()
        output = self.repo.path / "github-output.txt"
        blob = self.repo.git("hash-object", "-w", str(SOURCE / "Scripts/canary_release.py"))
        self.repo.git("tag", "canary-invalid", blob)
        result = subprocess.run(
            ["python3", str(SOURCE / "Scripts/canary_release.py"), "check",
             "--repo", str(self.repo.path), "--github-output", str(output)],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("merge-base --is-ancestor", result.stderr)
        self.assertFalse(output.exists())

    def test_check_writes_github_output(self):
        self.seed_release()
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "github-output.txt"
            run(
                [
                    "python3",
                    str(SOURCE / "Scripts" / "canary_release.py"),
                    "check",
                    "--repo",
                    str(self.repo.path),
                    "--github-output",
                    str(output),
                ]
            )
            content = output.read_text()
        self.assertIn("should_skip=true", content)
        self.assertIn("skip_reason=HEAD ", content)


class CanaryCITests(unittest.TestCase):
    def setUp(self):
        self.head = "a" * 40
        self.repository = "OmniNull/OmniWM"
        self.run = {
            "id": 100,
            "run_number": 10,
            "head_sha": self.head,
            "head_branch": "main",
            "event": "push",
            "path": ".github/workflows/ci.yml",
            "status": "completed",
            "conclusion": "success",
            "html_url": "https://github.com/OmniNull/OmniWM/actions/runs/100",
        }
        self.jobs = [
            {"name": name, "status": "completed", "conclusion": "success"}
            for name in ("Verify", "Tests")
        ]
        self.runs_path = (
            f"repos/{self.repository}/actions/workflows/ci.yml/runs"
            f"?branch=main&event=push&head_sha={self.head}&per_page=100"
        )
        self.jobs_path = f"repos/{self.repository}/actions/runs/100/jobs?filter=latest&per_page=100"
        self.responses = {
            self.runs_path: [{"workflow_runs": [self.run]}],
            self.jobs_path: [{"jobs": self.jobs}],
        }
        self.addCleanup(patch.stopall)
        self.git = patch.object(canary_release, "git", return_value=self.head).start()
        self.api = patch.object(canary_release, "github_api", side_effect=lambda path: self.responses[path]).start()

    def test_uses_checked_out_head_instead_of_event_sha(self):
        with patch.dict(os.environ, {"GITHUB_SHA": "b" * 40}):
            self.assertEqual(canary_release.verify_ci("checkout", self.repository), self.run)
        self.git.assert_called_once_with("checkout", "rev-parse", "HEAD")
        self.api.assert_any_call(self.runs_path)

    def test_missing_ci_is_rejected(self):
        self.responses[self.runs_path] = [{"workflow_runs": []}]
        with self.assertRaisesRegex(canary_release.CanaryError, "No OmniWM CI push run"):
            canary_release.verify_ci("checkout", self.repository)

    def test_success_for_another_commit_or_trigger_is_rejected(self):
        for field, value in (
            ("head_sha", "b" * 40),
            ("head_branch", "feature"),
            ("event", "pull_request"),
            ("path", ".github/workflows/website.yml"),
        ):
            with self.subTest(field=field):
                original = self.run[field]
                self.run[field] = value
                with self.assertRaisesRegex(canary_release.CanaryError, "does not match"):
                    canary_release.verify_ci("checkout", self.repository)
                self.run[field] = original

    def test_latest_failed_or_unfinished_run_blocks_an_older_success(self):
        older = {**self.run, "id": 99, "run_number": 9}
        self.responses[self.runs_path] = [{"workflow_runs": [older]}, {"workflow_runs": [self.run]}]
        for status, conclusion in (
            ("queued", None),
            ("in_progress", None),
            ("completed", "failure"),
            ("completed", "cancelled"),
            ("completed", "skipped"),
        ):
            with self.subTest(status=status, conclusion=conclusion):
                self.run.update(status=status, conclusion=conclusion)
                with self.assertRaisesRegex(canary_release.CanaryError, "has not succeeded"):
                    canary_release.verify_ci("checkout", self.repository)

    def test_latest_success_is_selected_across_run_pages(self):
        older = {**self.run, "id": 99, "run_number": 9, "conclusion": "failure"}
        self.responses[self.runs_path] = [{"workflow_runs": [self.run]}, {"workflow_runs": [older]}]
        self.assertEqual(canary_release.verify_ci("checkout", self.repository), self.run)

    def test_required_jobs_must_complete_successfully(self):
        for name in ("Verify", "Tests"):
            for status, conclusion in (("in_progress", None), ("completed", "failure"), ("completed", "skipped")):
                with self.subTest(name=name, status=status, conclusion=conclusion):
                    self.responses[self.jobs_path] = [{"jobs": [
                        {**job, "status": status, "conclusion": conclusion} if job["name"] == name else job
                        for job in self.jobs
                    ]}]
                    with self.assertRaisesRegex(canary_release.CanaryError, name):
                        canary_release.verify_ci("checkout", self.repository)

    def test_failing_duplicate_required_job_is_rejected(self):
        self.responses[self.jobs_path] = [{"jobs": self.jobs + [
            {"name": "Tests", "status": "completed", "conclusion": "failure"},
        ]}]
        with self.assertRaisesRegex(canary_release.CanaryError, "Tests"):
            canary_release.verify_ci("checkout", self.repository)

    def test_missing_required_job_is_rejected(self):
        for name in ("Verify", "Tests"):
            with self.subTest(name=name):
                self.responses[self.jobs_path] = [{"jobs": [job for job in self.jobs if job["name"] != name]}]
                with self.assertRaisesRegex(canary_release.CanaryError, name):
                    canary_release.verify_ci("checkout", self.repository)

    def test_required_jobs_on_later_pages_are_checked(self):
        self.responses[self.jobs_path] = [{"jobs": [self.jobs[0]]}, {"jobs": [self.jobs[1]]}]
        self.assertEqual(canary_release.verify_ci("checkout", self.repository), self.run)

    def test_forced_rebuild_still_requires_passing_ci(self):
        self.assertEqual(canary_release.check("checkout", True)["should_skip"], "false")
        self.run["conclusion"] = "failure"
        with self.assertRaisesRegex(canary_release.CanaryError, "has not succeeded"):
            canary_release.verify_ci("checkout", self.repository)

    def test_verify_ci_cli_reports_failure(self):
        self.run["conclusion"] = "failure"
        with patch.dict(os.environ, {"GITHUB_REPOSITORY": self.repository}), patch("sys.stderr", new_callable=io.StringIO) as errors:
            self.assertEqual(canary_release.main(["verify-ci", "--repo", "checkout"]), 2)
        self.assertIn("has not succeeded", errors.getvalue())


class CanaryCIAPITests(unittest.TestCase):
    def test_reads_all_api_pages(self):
        pages = [{"workflow_runs": []}, {"workflow_runs": [{"id": 100}]}]
        result = subprocess.CompletedProcess([], 0, json.dumps(pages), "")
        with patch.object(canary_release.subprocess, "run", return_value=result) as command:
            self.assertEqual(canary_release.github_api("repos/owner/repo/actions/runs"), pages)
        self.assertEqual(command.call_args.args[0], [
            "gh", "api", "--method", "GET", "--paginate", "--slurp", "repos/owner/repo/actions/runs",
        ])

    def test_api_failure_and_invalid_json_are_rejected(self):
        for code, output, errors in ((1, "", "HTTP 403"), (0, "not json", "")):
            with self.subTest(code=code), patch.object(
                canary_release.subprocess, "run", return_value=subprocess.CompletedProcess([], code, output, errors)
            ):
                with self.assertRaises(canary_release.CanaryError):
                    canary_release.github_api("repos/owner/repo/actions/runs")


if __name__ == "__main__":
    unittest.main()
