import os
from datetime import datetime

from atlassian import Confluence
from dotenv import load_dotenv

load_dotenv()

CONFLUENCE_API_TOKEN = os.getenv("CONFLUENCE_API_TOKEN")
CONFLUENCE_LOGIN = os.getenv("CONFLUENCE_LOGIN")
CONFLUENCE_URL = os.getenv("CONFLUENCE_URL")
CONFLUENCE_PAGE_TITLE = os.getenv("CONFLUENCE_PAGE_TITLE")
CONFLUENCE_PARENT_PAGE_ID = os.getenv("CONFLUENCE_PARENT_PAGE_ID")

# Set up the Confluence client
confluence = Confluence(
    url=CONFLUENCE_URL,
    username=CONFLUENCE_LOGIN,
    password=CONFLUENCE_API_TOKEN,
    cloud=True,
)

with open('out.txt', "r", encoding="utf-8") as f:
    page_content = f.read()

# Update or create the page
page = confluence.update_or_create(
    parent_id=CONFLUENCE_PARENT_PAGE_ID, title=CONFLUENCE_PAGE_TITLE, body=page_content, representation="wiki"
)

# Print the ID of the updated or created page
print(f'page id = {page["id"]}')
