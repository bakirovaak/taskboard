import os


class Settings:
    app_name: str = "TaskBoard"
    database_url: str = os.getenv(
        "DATABASE_URL",
        "postgresql+psycopg://taskboard:taskboard@localhost:5432/taskboard",
    )


settings = Settings()
