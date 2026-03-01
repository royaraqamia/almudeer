"""
Al-Mudeer - Pagination Utilities
Consistent pagination for all list endpoints
"""

from typing import TypeVar, Generic, List, Optional, Any, Dict
from dataclasses import dataclass
from math import ceil

T = TypeVar('T')


@dataclass
class PaginationParams:
    """Standard pagination parameters"""
    page: int = 1
    page_size: int = 20
    max_page_size: int = 100
    
    def __post_init__(self):
        # Enforce limits
        self.page = max(1, self.page)
        self.page_size = min(max(1, self.page_size), self.max_page_size)
    
    @property
    def offset(self) -> int:
        return (self.page - 1) * self.page_size
    
    @property
    def limit(self) -> int:
        return self.page_size


@dataclass
class PaginatedResponse(Generic[T]):
    """Standard paginated response structure"""
    items: List[T]
    total: int
    page: int
    page_size: int
    total_pages: int
    has_next: bool
    has_prev: bool
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "items": self.items,
            "pagination": {
                "total": self.total,
                "page": self.page,
                "page_size": self.page_size,
                "total_pages": self.total_pages,
                "has_next": self.has_next,
                "has_prev": self.has_prev,
            }
        }


def paginate(items: List[T], 
             total: int, 
             params: PaginationParams) -> PaginatedResponse[T]:
    """Create a paginated response from items"""
    total_pages = ceil(total / params.page_size) if total > 0 else 0
    
    return PaginatedResponse(
        items=items,
        total=total,
        page=params.page,
        page_size=params.page_size,
        total_pages=total_pages,
        has_next=params.page < total_pages,
        has_prev=params.page > 1,
    )


def get_pagination_sql(params: PaginationParams, db_type: str = "sqlite") -> str:
    """Generate SQL LIMIT/OFFSET clause for pagination"""
    if db_type == "postgresql":
        return f"LIMIT {params.limit} OFFSET {params.offset}"
    else:
        return f"LIMIT {params.limit} OFFSET {params.offset}"


async def get_total_count(table: str, where_clause: str = "", params: tuple = None) -> int:
    """Get total count for pagination"""
    from db_helper import get_db, fetch_one
    
    sql = f"SELECT COUNT(*) as count FROM {table}"
    if where_clause:
        sql += f" WHERE {where_clause}"
    
    async with get_db() as db:
        result = await fetch_one(db, sql, list(params) if params else [])
        return result["count"] if result else 0


# ============ Pre-built Pagination Functions ============

async def paginate_inbox(license_id: int, 
                         page: int = 1, 
                         page_size: int = 20,
                         channel: str = None,
                         is_read: bool = None) -> Dict[str, Any]:
    """Paginated inbox messages"""
    from db_helper import get_db, fetch_all
    import os
    
    params = PaginationParams(page=page, page_size=page_size)
    db_type = os.getenv("DB_TYPE", "sqlite").lower()
    
    # Build WHERE clause
    conditions = ["license_key_id = ?"]
    query_params = [license_id]
    
    if channel:
        conditions.append("channel = ?")
        query_params.append(channel)
    if is_read is not None:
        conditions.append("is_read = ?")
        query_params.append(is_read)
    
    where_clause = " AND ".join(conditions)
    
    # Get total count
    total = await get_total_count("inbox_messages", where_clause, tuple(query_params))
    
    # Get paginated items
    sql = f"""
        SELECT * FROM inbox_messages 
        WHERE {where_clause}
        ORDER BY created_at DESC
        {get_pagination_sql(params, db_type)}
    """
    
    async with get_db() as db:
        items = await fetch_all(db, sql, query_params)
    
    return paginate(items, total, params).to_dict()


async def paginate_crm(license_id: int,
                       page: int = 1,
                       page_size: int = 20) -> Dict[str, Any]:
    """Paginated CRM entries"""
    from db_helper import get_db, fetch_all
    import os
    
    params = PaginationParams(page=page, page_size=page_size)
    db_type = os.getenv("DB_TYPE", "sqlite").lower()
    
    total = await get_total_count("crm_entries", "license_id = ?", (license_id,))
    
    sql = f"""
        SELECT * FROM crm_entries 
        WHERE license_id = ?
        ORDER BY created_at DESC
        {get_pagination_sql(params, db_type)}
    """
    
    async with get_db() as db:
        items = await fetch_all(db, sql, [license_id])
    
    return paginate(items, total, params).to_dict()


async def paginate_customers(license_id: int,
                             page: int = 1,
                             page_size: int = 20,
                             search: str = None) -> Dict[str, Any]:
    """Paginated customers list"""
    from db_helper import get_db, fetch_all
    import os

    params = PaginationParams(page=page, page_size=page_size)
    db_type = os.getenv("DB_TYPE", "sqlite").lower()

    conditions = ["license_key_id = ?"]
    query_params = [license_id]

    if search:
        conditions.append("(name LIKE ? OR email LIKE ? OR phone LIKE ?)")
        search_pattern = f"%{search}%"
        query_params.extend([search_pattern, search_pattern, search_pattern])

    where_clause = " AND ".join(conditions)
    total = await get_total_count("customers", where_clause, tuple(query_params))

    sql = f"""
        SELECT *,
               (EXISTS (SELECT 1 FROM license_keys l WHERE l.username = customers.username AND customers.username IS NOT NULL)) as is_almudeer_user
        FROM customers
        WHERE {where_clause}
        ORDER BY created_at DESC
        {get_pagination_sql(params, db_type)}
    """

    async with get_db() as db:
        items = await fetch_all(db, sql, query_params)

    # Calculate pagination details
    paginated = paginate(items, total, params)

    # Return legacy format matching frontend expectation
    return {
        "customers": paginated.items,
        "total": paginated.total,
        "has_more": paginated.has_next,
        "page": paginated.page,
        "total_pages": paginated.total_pages
    }
