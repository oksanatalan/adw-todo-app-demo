# frozen_string_literal: true

require_relative "../../test_helper"

class BranchNameTest < Minitest::Test
  def test_generates_standard_branch_name
    name = Adw::BranchName.generate("feat", 42, "abc12345", "Add user authentication")
    assert_equal "feat-42-abc12345-add-user-authentication", name
  end

  def test_strips_special_characters
    name = Adw::BranchName.generate("bug", 7, "xyz99999", "Fix login error! (critical)")
    assert_equal "bug-7-xyz99999-fix-login-error-critical", name
  end

  def test_limits_to_5_words
    name = Adw::BranchName.generate("feat", 1, "a1b2c3d4", "This is a very long issue title with many words")
    assert_equal "feat-1-a1b2c3d4-this-is-a-very-long", name
  end

  def test_handles_empty_title
    name = Adw::BranchName.generate("chore", 10, "deadbeef", "")
    assert_equal "chore-10-deadbeef-task", name
  end

  def test_handles_non_latin_title
    name = Adw::BranchName.generate("feat", 5, "abcd1234", "!!!")
    assert_equal "feat-5-abcd1234-task", name
  end

  def test_deterministic
    name1 = Adw::BranchName.generate("feat", 42, "abc", "Add login")
    name2 = Adw::BranchName.generate("feat", 42, "abc", "Add login")
    assert_equal name1, name2
  end
end
