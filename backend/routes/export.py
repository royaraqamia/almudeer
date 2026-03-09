"""
Al-Mudeer - Export & Reports Routes
PDF, Excel, CSV export functionality
"""

from fastapi import APIRouter, HTTPException, Depends
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime, timedelta
import io
import csv
import json
import html

from dependencies import get_license_from_header
from db_helper import get_db, fetch_all, fetch_one, DB_TYPE
from utils.date_utils import to_hijri_date_string

router = APIRouter(prefix="/api/export", tags=["Export"])


# ============ Schemas ============

class ExportRequest(BaseModel):
    start_date: Optional[str] = None  # ISO format: YYYY-MM-DD
    end_date: Optional[str] = None
    export_type: str = Field(default="csv", description="csv, json, or html")


# ============ Helper Functions ============

def get_date_range(start_date: str = None, end_date: str = None, days: int = 30):
    """Parse date range or use defaults"""
    if end_date:
        end = datetime.fromisoformat(end_date)
    else:
        end = datetime.now()
    
    if start_date:
        start = datetime.fromisoformat(start_date)
    else:
        start = end - timedelta(days=days)
    
    return start, end


async def get_export_data(license_id: int, start: datetime, end: datetime):
    """Fetch all data for export (works with SQLite and PostgreSQL)."""
    data = {
        "period": {
            "start": start.isoformat(),
            "end": end.isoformat(),
        },
        "analytics": {},
        "customers": [],
        "messages": [],
        "crm_entries": [],
    }

    # For PostgreSQL we pass real date/datetime objects; for SQLite we use ISO strings.
    if DB_TYPE == "postgresql":
        date_start = start.date()
        date_end = end.date()
        ts_start = start
        ts_end = end
    else:
        date_start = start.date().isoformat()
        date_end = end.date().isoformat()
        ts_start = start.isoformat()
        ts_end = end.isoformat()

    async with get_db() as db:
        # Analytics summary
        analytics_row = await fetch_one(
            db,
            """
            SELECT 
                SUM(messages_received) as total_received,
                SUM(messages_replied) as total_replied,
                SUM(auto_replies) as auto_replies,
                SUM(positive_sentiment) as positive,
                SUM(negative_sentiment) as negative,
                SUM(neutral_sentiment) as neutral,
                SUM(time_saved_seconds) as time_saved
            FROM analytics 
            WHERE license_key_id = ? 
              AND date BETWEEN ? AND ?
            """,
            [license_id, date_start, date_end],
        )
        if analytics_row:
            data["analytics"] = analytics_row

        # Customers
        data["customers"] = await fetch_all(
            db,
            """
            SELECT * FROM customers 
            WHERE license_key_id = ?
            ORDER BY name ASC
            """,
            [license_id],
        )

        # Inbox messages in date range
        data["messages"] = await fetch_all(
            db,
            """
            SELECT * FROM inbox_messages 
            WHERE license_key_id = ?
              AND created_at BETWEEN ? AND ?
            ORDER BY created_at DESC
            """,
            [license_id, ts_start, ts_end],
        )

        # CRM entries in date range
        data["crm_entries"] = await fetch_all(
            db,
            """
            SELECT * FROM crm_entries 
            WHERE license_key_id = ?
              AND created_at BETWEEN ? AND ?
            ORDER BY created_at DESC
            """,
            [license_id, ts_start, ts_end],
        )

    return data


def generate_csv(data: dict, data_type: str) -> str:
    """Generate CSV content with UTF-8 BOM for Excel compatibility"""
    output = io.StringIO()
    # Add UTF-8 BOM for Excel to properly recognize Arabic text
    output.write('\ufeff')
    
    if data_type == "customers":
        fieldnames = ["id", "name", "phone", "email", "company", "is_vip", "created_at"]
        writer = csv.DictWriter(output, fieldnames=fieldnames, extrasaction='ignore')
        writer.writeheader()
        for customer in data.get("customers", []):
            writer.writerow(customer)
    
    elif data_type == "messages":
        fieldnames = ["id", "channel", "sender_name", "sender_contact", "subject", "body", "intent", "sentiment", "status", "created_at"]
        writer = csv.DictWriter(output, fieldnames=fieldnames, extrasaction='ignore')
        writer.writeheader()
        for msg in data.get("messages", []):
            writer.writerow(msg)
    
    elif data_type == "crm":
        fieldnames = ["id", "sender_name", "sender_contact", "message_type", "intent", "status", "created_at"]
        writer = csv.DictWriter(output, fieldnames=fieldnames, extrasaction='ignore')
        writer.writeheader()
        for entry in data.get("crm_entries", []):
            writer.writerow(entry)
    
    elif data_type == "analytics":
        writer = csv.writer(output)
        writer.writerow(["المقياس", "القيمة"])
        analytics = data.get("analytics", {})
        writer.writerow(["الرسائل المستلمة", analytics.get("total_received", 0)])
        writer.writerow(["الرسائل المردود عليها", analytics.get("total_replied", 0)])
        writer.writerow(["الردود التلقائية", analytics.get("auto_replies", 0)])
        writer.writerow(["المشاعر الإيجابية", analytics.get("positive", 0)])
        writer.writerow(["المشاعر السلبية", analytics.get("negative", 0)])
        writer.writerow(["المشاعر المحايدة", analytics.get("neutral", 0)])
        writer.writerow(["الوقت الموفر (ثواني)", analytics.get("time_saved", 0)])
    
    return output.getvalue()


def generate_html_report(data: dict, license_name: str = "شركتك") -> str:
    """Generate HTML report"""
    analytics = data.get("analytics", {})
    customers = data.get("customers", [])
    messages = data.get("messages", [])
    period = data.get("period", {})
    
    # Convert period dates to Hijri
    start_iso = period.get('start')
    end_iso = period.get('end')
    start_hijri = ""
    end_hijri = ""
    
    if start_iso:
        try:
            start_dt = datetime.fromisoformat(start_iso)
            start_hijri = to_hijri_date_string(start_dt)
        except:
            start_hijri = start_iso[:10]
            
    if end_iso:
        try:
            end_dt = datetime.fromisoformat(end_iso)
            end_hijri = to_hijri_date_string(end_dt)
        except:
            end_hijri = end_iso[:10]

    # Footer timestamp
    now = datetime.now()
    footer_date = to_hijri_date_string(now)
    footer_time = now.strftime("%I:%M %p").replace("AM", "ص").replace("PM", "م")

    html = f"""
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
    <meta charset="UTF-8">
    <title>تقرير المدير - {html.escape(license_name)}</title>
    <style>
        * {{ font-family: 'Segoe UI', Tahoma, sans-serif; }}
        body {{ max-width: 800px; margin: 0 auto; padding: 20px; background: #f5f5f5; }}
        .header {{ text-align: center; padding: 20px; background: linear-gradient(135deg, #1e40af, #3b82f6); color: white; border-radius: 10px; margin-bottom: 20px; }}
        .card {{ background: white; padding: 20px; border-radius: 10px; margin-bottom: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
        .stats {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; }}
        .stat {{ text-align: center; padding: 15px; background: #f8fafc; border-radius: 8px; }}
        .stat-value {{ font-size: 2em; font-weight: bold; color: #1e40af; }}
        .stat-label {{ color: #64748b; font-size: 0.9em; }}
        table {{ width: 100%; border-collapse: collapse; }}
        th, td {{ padding: 10px; text-align: right; border-bottom: 1px solid #e2e8f0; }}
        th {{ background: #f1f5f9; font-weight: 600; }}
        .badge {{ display: inline-block; padding: 2px 8px; border-radius: 10px; font-size: 0.8em; }}
        .badge-positive {{ background: #dcfce7; color: #166534; }}
        .badge-negative {{ background: #fee2e2; color: #991b1b; }}
        .footer {{ text-align: center; color: #64748b; font-size: 0.9em; margin-top: 20px; }}
    </style>
</head>
<body>
    <div class="header">
        <h1>🏢 تقرير المدير</h1>
        <p>{html.escape(license_name)}</p>
        <p>الفترة: {html.escape(start_hijri)} إلى {html.escape(end_hijri)}</p>
    </div>
    
    <div class="card">
        <h2>📊 ملخص الإحصائيات</h2>
        <div class="stats">
            <div class="stat">
                <div class="stat-value">{analytics.get('total_received', 0) or 0}</div>
                <div class="stat-label">رسالة مستلمة</div>
            </div>
            <div class="stat">
                <div class="stat-value">{analytics.get('total_replied', 0) or 0}</div>
                <div class="stat-label">تم الرد عليها</div>
            </div>
            <div class="stat">
                <div class="stat-value">{round((analytics.get('time_saved', 0) or 0) / 3600, 1)}</div>
                <div class="stat-label">ساعة موفرة</div>
            </div>
        </div>
    </div>
    
    <div class="card">
        <h2>😊 تحليل المشاعر</h2>
        <div class="stats">
            <div class="stat">
                <div class="stat-value" style="color: #16a34a;">{analytics.get('positive', 0) or 0}</div>
                <div class="stat-label">إيجابي</div>
            </div>
            <div class="stat">
                <div class="stat-value" style="color: #64748b;">{analytics.get('neutral', 0) or 0}</div>
                <div class="stat-label">محايد</div>
            </div>
            <div class="stat">
                <div class="stat-value" style="color: #dc2626;">{analytics.get('negative', 0) or 0}</div>
                <div class="stat-label">سلبي</div>
            </div>
        </div>
    </div>
    
    <div class="card">
        <h2>👥 أفضل العملاء ({len(customers[:10])})</h2>
        <table>
            <tr>
                <th>الاسم</th>
                <th>VIP</th>
            </tr>
            {''.join(f'''
            <tr>
                <td>{html.escape(c.get('name', 'بدون اسم'))}</td>
                <td>{'⭐' if c.get('is_vip') else '-'}</td>
            </tr>
            ''' for c in customers[:10])}
        </table>
    </div>
    
    <div class="card">
        <h2>📨 آخر الرسائل ({len(messages[:20])})</h2>
        <table>
            <tr>
                <th>المرسل</th>
                <th>القناة</th>
                <th>النية</th>
                <th>المشاعر</th>
            </tr>
            {''.join(f'''
            <tr>
                <td>{html.escape(m.get('sender_name', 'مجهول'))}</td>
                <td>{html.escape(m.get('channel', '-'))}</td>
                <td>{html.escape(m.get('intent', '-'))}</td>
                <td><span class="badge {'badge-positive' if m.get('sentiment') == 'إيجابي' else 'badge-negative' if m.get('sentiment') == 'سلبي' else ''}">{html.escape(m.get('sentiment', '-'))}</span></td>
            </tr>
            ''' for m in messages[:20])}
        </table>
    </div>
    
    <div class="footer">
        <p>تم إنشاء هذا التقرير بواسطة المدير - {html.escape(footer_date)} {html.escape(footer_time)}</p>
    </div>
</body>
</html>
"""
    return html


# ============ Routes ============

@router.get("/customers")
async def export_customers(
    format: str = "csv",
    license: dict = Depends(get_license_from_header)
):
    """Export customers list"""
    start, end = get_date_range(days=365)  # All customers
    data = await get_export_data(license["license_id"], start, end)
    
    if format == "json":
        return {"customers": data["customers"]}
    
    elif format == "csv":
        csv_content = generate_csv(data, "customers")
        return StreamingResponse(
            io.StringIO(csv_content),
            media_type="text/csv; charset=utf-8",
            headers={"Content-Disposition": "attachment; filename=customers.csv"}
        )
    
    raise HTTPException(status_code=400, detail="صيغة غير مدعومة")


@router.get("/messages")
async def export_messages(
    format: str = "csv",
    start_date: str = None,
    end_date: str = None,
    license: dict = Depends(get_license_from_header)
):
    """Export messages"""
    start, end = get_date_range(start_date, end_date, days=30)
    data = await get_export_data(license["license_id"], start, end)
    
    if format == "json":
        return {"messages": data["messages"], "period": data["period"]}
    
    elif format == "csv":
        csv_content = generate_csv(data, "messages")
        return StreamingResponse(
            io.StringIO(csv_content),
            media_type="text/csv; charset=utf-8",
            headers={"Content-Disposition": "attachment; filename=messages.csv"}
        )
    
    raise HTTPException(status_code=400, detail="صيغة غير مدعومة")


@router.get("/crm")
async def export_crm(
    format: str = "csv",
    start_date: str = None,
    end_date: str = None,
    license: dict = Depends(get_license_from_header)
):
    """Export CRM entries"""
    start, end = get_date_range(start_date, end_date, days=30)
    data = await get_export_data(license["license_id"], start, end)
    
    if format == "json":
        return {"crm_entries": data["crm_entries"], "period": data["period"]}
    
    elif format == "csv":
        csv_content = generate_csv(data, "crm")
        return StreamingResponse(
            io.StringIO(csv_content),
            media_type="text/csv; charset=utf-8",
            headers={"Content-Disposition": "attachment; filename=crm.csv"}
        )
    
    raise HTTPException(status_code=400, detail="صيغة غير مدعومة")


@router.get("/analytics")
async def export_analytics(
    format: str = "csv",
    start_date: str = None,
    end_date: str = None,
    license: dict = Depends(get_license_from_header)
):
    """Export analytics summary"""
    start, end = get_date_range(start_date, end_date, days=30)
    data = await get_export_data(license["license_id"], start, end)
    
    if format == "json":
        return {"analytics": data["analytics"], "period": data["period"]}
    
    elif format == "csv":
        csv_content = generate_csv(data, "analytics")
        return StreamingResponse(
            io.StringIO(csv_content),
            media_type="text/csv; charset=utf-8",
            headers={"Content-Disposition": "attachment; filename=analytics.csv"}
        )
    
    raise HTTPException(status_code=400, detail="صيغة غير مدعومة")


@router.get("/report")
async def generate_full_report(
    start_date: str = None,
    end_date: str = None,
    license: dict = Depends(get_license_from_header)
):
    """Generate full HTML report"""
    start, end = get_date_range(start_date, end_date, days=30)
    data = await get_export_data(license["license_id"], start, end)
    
    html = generate_html_report(data, license.get("full_name", "شركتك"))
    
    return StreamingResponse(
        io.StringIO(html),
        media_type="text/html",
        headers={"Content-Disposition": "attachment; filename=report.html"}
    )


@router.get("/report/preview")
async def preview_report(
    start_date: str = None,
    end_date: str = None,
    license: dict = Depends(get_license_from_header)
):
    """Preview HTML report in browser"""
    start, end = get_date_range(start_date, end_date, days=30)
    data = await get_export_data(license["license_id"], start, end)
    
    html = generate_html_report(data, license.get("full_name", "شركتك"))
    
    return StreamingResponse(
        io.StringIO(html),
        media_type="text/html"
    )

