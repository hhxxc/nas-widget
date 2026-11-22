"""NAS 待办 API：为 Windows 网页与 iOS 小组件提供待办数据（SQLite 存储 + X-Api-Key 鉴权）"""
import os
import sqlite3
import time
import uuid
from pathlib import Path

from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

API_KEY = os.environ.get("API_KEY", "")
DATA_DIR = Path(os.environ.get("DATA_DIR", str(Path(__file__).resolve().parent.parent / "data")))
WEB_DIR = Path(os.environ.get("WEB_DIR", str(Path(__file__).resolve().parent.parent / "web")))
DB_PATH = DATA_DIR / "todos.db"
DATA_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="NAS Widget API", docs_url=None, redoc_url=None)


def get_db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute(
        """CREATE TABLE IF NOT EXISTS todos (
            id TEXT PRIMARY KEY,
            content TEXT NOT NULL,
            done INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL
        )"""
    )
    return conn


def require_key(x_api_key: str = Header(default="")) -> None:
    if API_KEY and x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="invalid api key")


def row_to_dict(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "content": row["content"],
        "done": bool(row["done"]),
        "createdAt": row["created_at"],
    }


class TodoIn(BaseModel):
    content: str = Field(min_length=1, max_length=200)


class TodoPatch(BaseModel):
    content: str | None = Field(default=None, min_length=1, max_length=200)
    done: bool | None = None


@app.get("/api/health")
def health():
    return {"ok": True, "time": int(time.time())}


@app.get("/api/todos", dependencies=[Depends(require_key)])
def list_todos():
    conn = get_db()
    try:
        rows = conn.execute("SELECT * FROM todos ORDER BY done ASC, created_at DESC").fetchall()
        return {"items": [row_to_dict(r) for r in rows]}
    finally:
        conn.close()


@app.post("/api/todos", dependencies=[Depends(require_key)])
def add_todo(todo: TodoIn):
    item_id = uuid.uuid4().hex[:12]
    conn = get_db()
    try:
        conn.execute(
            "INSERT INTO todos (id, content, done, created_at) VALUES (?, ?, 0, ?)",
            (item_id, todo.content.strip(), time.time()),
        )
        conn.commit()
        row = conn.execute("SELECT * FROM todos WHERE id = ?", (item_id,)).fetchone()
        return {"item": row_to_dict(row)}
    finally:
        conn.close()


@app.patch("/api/todos/{item_id}", dependencies=[Depends(require_key)])
def patch_todo(item_id: str, patch: TodoPatch):
    conn = get_db()
    try:
        row = conn.execute("SELECT * FROM todos WHERE id = ?", (item_id,)).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="todo not found")
        content = patch.content.strip() if patch.content is not None else row["content"]
        done = int(patch.done) if patch.done is not None else row["done"]
        conn.execute("UPDATE todos SET content = ?, done = ? WHERE id = ?", (content, done, item_id))
        conn.commit()
        row = conn.execute("SELECT * FROM todos WHERE id = ?", (item_id,)).fetchone()
        return {"item": row_to_dict(row)}
    finally:
        conn.close()


@app.delete("/api/todos/{item_id}", dependencies=[Depends(require_key)])
def delete_todo(item_id: str):
    conn = get_db()
    try:
        cur = conn.execute("DELETE FROM todos WHERE id = ?", (item_id,))
        conn.commit()
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="todo not found")
        return {"ok": True}
    finally:
        conn.close()


app.mount("/", StaticFiles(directory=str(WEB_DIR), html=True), name="web")
