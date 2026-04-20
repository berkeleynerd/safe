"""Ceiling-priority fixture classification for restricted test hosts."""

from __future__ import annotations

from pathlib import Path

from _lib.test_harness import REPO_ROOT

# Fixtures that require a host/container capable of real-time priority setup.
# Keep this list explicit and greppable. Some entries are preemptive for
# container variants where the ceiling-priority failure appears even when this
# host can run them successfully with RLIMIT_RTPRIO=0.
CEILING_PRIORITY_FIXTURES = {
    REPO_ROOT / "tests" / "build" / "pr118c2_package_build.safe",
    REPO_ROOT / "tests" / "build" / "pr118c2_entry_build.safe",
    REPO_ROOT / "tests" / "build" / "pr118c2_package_pre_task.safe",
    REPO_ROOT / "tests" / "build" / "pr1112a_shared_task_build.safe",
    REPO_ROOT / "tests" / "build" / "pr1112b_shared_update_build.safe",
    REPO_ROOT / "tests" / "build" / "pr227_shared_snapshot_order_build.safe",
    REPO_ROOT / "tests" / "build" / "pr227_public_shared_snapshot_order_build.safe",
    REPO_ROOT / "tests" / "build" / "pr228_shared_field_condition_build.safe",
    REPO_ROOT / "tests" / "build" / "pr228_imported_shared_condition_build.safe",
    REPO_ROOT / "tests" / "build" / "pr228_shared_loop_exit_condition_build.safe",
    REPO_ROOT / "tests" / "build" / "pr1112c_shared_string_build.safe",
    REPO_ROOT / "tests" / "build" / "pr1112c_shared_container_fields_build.safe",
    REPO_ROOT / "tests" / "build" / "pr1112c_layered_growable_type_build.safe",
    REPO_ROOT / "tests" / "build" / "pr1122f2_shared_bounded_string_field_build.safe",
    REPO_ROOT / "tests" / "build" / "pr1122f2_shared_optional_string_none_build.safe",
    REPO_ROOT / "tests" / "build" / "pr1112d_shared_list_root_build.safe",
    REPO_ROOT / "tests" / "build" / "pr1112d_shared_map_root_build.safe",
    REPO_ROOT / "tests" / "build" / "pr1112d_shared_map_indexed_remove_build.safe",
    REPO_ROOT / "tests" / "build" / "pr1112d_shared_growable_root_build.safe",
    REPO_ROOT / "tests" / "build" / "pr1112e_imported_shared_record_build.safe",
    REPO_ROOT / "tests" / "build" / "pr1112e_imported_shared_list_build.safe",
    REPO_ROOT / "tests" / "build" / "pr1112e_imported_shared_map_build.safe",
    REPO_ROOT / "tests" / "build" / "pr1112f_shared_record_ceiling_build.safe",
    REPO_ROOT / "tests" / "build" / "pr1112f_shared_container_ceiling_build.safe",
    REPO_ROOT / "tests" / "build" / "pr1112f_mixed_channel_shared_build.safe",
    REPO_ROOT / "tests" / "interfaces" / "pr119a_select_delay_receive.safe",
    REPO_ROOT / "tests" / "interfaces" / "pr119a_select_delay_timeout.safe",
    REPO_ROOT / "tests" / "interfaces" / "pr119a_select_zero_delay_ready.safe",
    REPO_ROOT / "tests" / "build" / "pr230_top_level_select_delay_build.safe",
    REPO_ROOT / "tests" / "build" / "pr118g_string_channel_build.safe",
    REPO_ROOT / "tests" / "build" / "pr118g_tuple_string_channel_build.safe",
    REPO_ROOT / "tests" / "build" / "pr118g_record_string_channel_build.safe",
    REPO_ROOT / "tests" / "build" / "pr118g_try_string_channel_build.safe",
    REPO_ROOT / "tests" / "build" / "pr119d_send_single_eval_build.safe",
    REPO_ROOT / "tests" / "build" / "pr331_shared_initializer_effect_pollution_build.safe",
}


def is_ceiling_priority_fixture(path: Path) -> bool:
    return path in CEILING_PRIORITY_FIXTURES
