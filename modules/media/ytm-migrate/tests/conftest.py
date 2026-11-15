import shutil
from pathlib import Path

import pytest

FIXTURE = Path(__file__).parent / "fixtures" / "takeout"


@pytest.fixture
def takeout_zip(tmp_path):
    base = tmp_path / "takeout"
    shutil.make_archive(str(base), "zip", FIXTURE)
    return base.with_suffix(".zip")
