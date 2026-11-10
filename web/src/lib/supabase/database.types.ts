
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "graphql_public": {
          Tables: {
            [_ in never]: never
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "graphql":
{ Args: { "extensions"?: Json,"operationName"?: string,"query"?: string,"variables"?: Json }; Returns: Json
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        },"public": {
          Tables: {
            "billing_customers": {
                  Row: {
                    "created_at": string,"customer_id": string,"provider": Database["public"]['Enums']["payment_provider"],"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"customer_id": string,"provider": Database["public"]['Enums']["payment_provider"],"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"customer_id"?: string,"provider"?: Database["public"]['Enums']["payment_provider"],"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "billing_customers_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"chapter_pages": {
                  Row: {
                    "chapter_id": string,"created_at": string,"height": number,"id": string,"position": number,"storage_path": string,"width": number
                  }
                  ComputedFields: never
                  Insert: {
                    "chapter_id": string,"created_at"?: string,"height": number,"id"?: string,"position": number,"storage_path": string,"width": number
                  }
                  Update: {
                    "chapter_id"?: string,"created_at"?: string,"height"?: number,"id"?: string,"position"?: number,"storage_path"?: string,"width"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "chapter_pages_chapter_id_fkey"
      columns: ["chapter_id"]
isOneToOne: false
      referencedRelation: "chapters"
      referencedColumns: ["id"]
    }
                  ]
                },"chapter_reads": {
                  Row: {
                    "access_reason": string,"chapter_id": string,"created_at": string,"creator_id": string,"period": string,"series_id": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "access_reason": string,"chapter_id": string,"created_at"?: string,"creator_id": string,"period": string,"series_id": string,"user_id": string
                  }
                  Update: {
                    "access_reason"?: string,"chapter_id"?: string,"created_at"?: string,"creator_id"?: string,"period"?: string,"series_id"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "chapter_reads_chapter_id_fkey"
      columns: ["chapter_id"]
isOneToOne: false
      referencedRelation: "chapters"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "chapter_reads_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "chapter_reads_series_id_fkey"
      columns: ["series_id"]
isOneToOne: false
      referencedRelation: "series"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "chapter_reads_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"chapter_unlocks": {
                  Row: {
                    "chapter_id": string,"coins_spent": number,"created_at": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "chapter_id": string,"coins_spent": number,"created_at"?: string,"user_id": string
                  }
                  Update: {
                    "chapter_id"?: string,"coins_spent"?: number,"created_at"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "chapter_unlocks_chapter_id_fkey"
      columns: ["chapter_id"]
isOneToOne: false
      referencedRelation: "chapters"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "chapter_unlocks_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"chapters": {
                  Row: {
                    "access": Database["public"]['Enums']["chapter_access"],"coin_price": number,"created_at": string,"early_access_until": string | null,"id": string,"number": number,"publish_at": string,"published": boolean,"series_id": string,"title": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "access"?: Database["public"]['Enums']["chapter_access"],"coin_price"?: number,"created_at"?: string,"early_access_until"?: string | null,"id"?: string,"number": number,"publish_at"?: string,"published"?: boolean,"series_id": string,"title"?: string,"updated_at"?: string
                  }
                  Update: {
                    "access"?: Database["public"]['Enums']["chapter_access"],"coin_price"?: number,"created_at"?: string,"early_access_until"?: string | null,"id"?: string,"number"?: number,"publish_at"?: string,"published"?: boolean,"series_id"?: string,"title"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "chapters_series_id_fkey"
      columns: ["series_id"]
isOneToOne: false
      referencedRelation: "series"
      referencedColumns: ["id"]
    }
                  ]
                },"coin_balances": {
                  Row: {
                    "balance": number,"updated_at": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "balance"?: number,"updated_at"?: string,"user_id": string
                  }
                  Update: {
                    "balance"?: number,"updated_at"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "coin_balances_user_id_fkey"
      columns: ["user_id"]
isOneToOne: true
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"coin_transactions": {
                  Row: {
                    "amount": number,"balance_after": number,"chapter_id": string | null,"created_at": string,"id": string,"note": string | null,"plan_id": string | null,"provider": Database["public"]['Enums']["payment_provider"] | null,"provider_ref": string | null,"type": Database["public"]['Enums']["coin_tx_type"],"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "amount": number,"balance_after": number,"chapter_id"?: string | null,"created_at"?: string,"id"?: string,"note"?: string | null,"plan_id"?: string | null,"provider"?: Database["public"]['Enums']["payment_provider"] | null,"provider_ref"?: string | null,"type": Database["public"]['Enums']["coin_tx_type"],"user_id": string
                  }
                  Update: {
                    "amount"?: number,"balance_after"?: number,"chapter_id"?: string | null,"created_at"?: string,"id"?: string,"note"?: string | null,"plan_id"?: string | null,"provider"?: Database["public"]['Enums']["payment_provider"] | null,"provider_ref"?: string | null,"type"?: Database["public"]['Enums']["coin_tx_type"],"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "coin_transactions_chapter_id_fkey"
      columns: ["chapter_id"]
isOneToOne: false
      referencedRelation: "chapters"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "coin_transactions_plan_id_fkey"
      columns: ["plan_id"]
isOneToOne: false
      referencedRelation: "pricing_plans"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "coin_transactions_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"creator_earnings": {
                  Row: {
                    "chapter_id": string | null,"created_at": string,"creator_cents": number,"creator_id": string,"gross_cents": number,"id": string,"period": string,"platform_cents": number,"ref": string,"series_id": string | null,"share_pct": number,"source": Database["public"]['Enums']["earning_source"]
                  }
                  ComputedFields: never
                  Insert: {
                    "chapter_id"?: string | null,"created_at"?: string,"creator_cents": number,"creator_id": string,"gross_cents": number,"id"?: string,"period": string,"platform_cents": number,"ref": string,"series_id"?: string | null,"share_pct": number,"source": Database["public"]['Enums']["earning_source"]
                  }
                  Update: {
                    "chapter_id"?: string | null,"created_at"?: string,"creator_cents"?: number,"creator_id"?: string,"gross_cents"?: number,"id"?: string,"period"?: string,"platform_cents"?: number,"ref"?: string,"series_id"?: string | null,"share_pct"?: number,"source"?: Database["public"]['Enums']["earning_source"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "creator_earnings_chapter_id_fkey"
      columns: ["chapter_id"]
isOneToOne: false
      referencedRelation: "chapters"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "creator_earnings_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "creator_earnings_series_id_fkey"
      columns: ["series_id"]
isOneToOne: false
      referencedRelation: "series"
      referencedColumns: ["id"]
    }
                  ]
                },"creators": {
                  Row: {
                    "application_note": string,"bio": string,"created_at": string,"id": string,"pen_name": string,"portfolio_url": string | null,"revenue_share_pct": number | null,"reviewed_at": string | null,"reviewed_by": string | null,"status": Database["public"]['Enums']["creator_status"]
                  }
                  ComputedFields: never
                  Insert: {
                    "application_note"?: string,"bio"?: string,"created_at"?: string,"id": string,"pen_name": string,"portfolio_url"?: string | null,"revenue_share_pct"?: number | null,"reviewed_at"?: string | null,"reviewed_by"?: string | null,"status"?: Database["public"]['Enums']["creator_status"]
                  }
                  Update: {
                    "application_note"?: string,"bio"?: string,"created_at"?: string,"id"?: string,"pen_name"?: string,"portfolio_url"?: string | null,"revenue_share_pct"?: number | null,"reviewed_at"?: string | null,"reviewed_by"?: string | null,"status"?: Database["public"]['Enums']["creator_status"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "creators_id_fkey"
      columns: ["id"]
isOneToOne: true
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "creators_reviewed_by_fkey"
      columns: ["reviewed_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"follows": {
                  Row: {
                    "created_at": string,"series_id": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"series_id": string,"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"series_id"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "follows_series_id_fkey"
      columns: ["series_id"]
isOneToOne: false
      referencedRelation: "series"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "follows_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"payments": {
                  Row: {
                    "amount_cents": number,"created_at": string,"currency": string,"id": string,"kind": Database["public"]['Enums']["plan_kind"],"period": string,"plan_id": string | null,"provider": Database["public"]['Enums']["payment_provider"],"provider_ref": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "amount_cents": number,"created_at"?: string,"currency"?: string,"id"?: string,"kind": Database["public"]['Enums']["plan_kind"],"period": string,"plan_id"?: string | null,"provider": Database["public"]['Enums']["payment_provider"],"provider_ref": string,"user_id": string
                  }
                  Update: {
                    "amount_cents"?: number,"created_at"?: string,"currency"?: string,"id"?: string,"kind"?: Database["public"]['Enums']["plan_kind"],"period"?: string,"plan_id"?: string | null,"provider"?: Database["public"]['Enums']["payment_provider"],"provider_ref"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "payments_plan_id_fkey"
      columns: ["plan_id"]
isOneToOne: false
      referencedRelation: "pricing_plans"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payments_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"platform_settings": {
                  Row: {
                    "key": string,"updated_at": string,"value": NonNullable<Json>
                  }
                  ComputedFields: never
                  Insert: {
                    "key": string,"updated_at"?: string,"value": NonNullable<Json>
                  }
                  Update: {
                    "key"?: string,"updated_at"?: string,"value"?: NonNullable<Json>
                  }
                  Relationships: [
                    
                  ]
                },"pricing_plans": {
                  Row: {
                    "active": boolean,"code": string,"coins": number | null,"currency": string,"id": string,"kind": Database["public"]['Enums']["plan_kind"],"name": string,"price_cents": number,"sort": number,"stripe_price_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"code": string,"coins"?: number | null,"currency"?: string,"id"?: string,"kind": Database["public"]['Enums']["plan_kind"],"name": string,"price_cents": number,"sort"?: number,"stripe_price_id"?: string | null
                  }
                  Update: {
                    "active"?: boolean,"code"?: string,"coins"?: number | null,"currency"?: string,"id"?: string,"kind"?: Database["public"]['Enums']["plan_kind"],"name"?: string,"price_cents"?: number,"sort"?: number,"stripe_price_id"?: string | null
                  }
                  Relationships: [
                    
                  ]
                },"processed_payment_events": {
                  Row: {
                    "event_id": string,"processed_at": string,"provider": string,"type": string
                  }
                  ComputedFields: never
                  Insert: {
                    "event_id": string,"processed_at"?: string,"provider": string,"type": string
                  }
                  Update: {
                    "event_id"?: string,"processed_at"?: string,"provider"?: string,"type"?: string
                  }
                  Relationships: [
                    
                  ]
                },"profiles": {
                  Row: {
                    "avatar_url": string | null,"created_at": string,"display_name": string,"id": string,"locale": string,"role": Database["public"]['Enums']["user_role"],"username": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "avatar_url"?: string | null,"created_at"?: string,"display_name"?: string,"id": string,"locale"?: string,"role"?: Database["public"]['Enums']["user_role"],"username"?: string | null
                  }
                  Update: {
                    "avatar_url"?: string | null,"created_at"?: string,"display_name"?: string,"id"?: string,"locale"?: string,"role"?: Database["public"]['Enums']["user_role"],"username"?: string | null
                  }
                  Relationships: [
                    
                  ]
                },"reading_progress": {
                  Row: {
                    "chapter_id": string,"completed": boolean,"page_index": number,"scroll_ratio": number,"series_id": string,"updated_at": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "chapter_id": string,"completed"?: boolean,"page_index"?: number,"scroll_ratio"?: number,"series_id": string,"updated_at"?: string,"user_id": string
                  }
                  Update: {
                    "chapter_id"?: string,"completed"?: boolean,"page_index"?: number,"scroll_ratio"?: number,"series_id"?: string,"updated_at"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "reading_progress_chapter_id_fkey"
      columns: ["chapter_id"]
isOneToOne: false
      referencedRelation: "chapters"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "reading_progress_series_id_fkey"
      columns: ["series_id"]
isOneToOne: false
      referencedRelation: "series"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "reading_progress_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"series": {
                  Row: {
                    "cover_path": string | null,"created_at": string,"creator_id": string,"description": string,"free_chapters": number,"genres": (string)[],"hidden_by_admin": boolean,"id": string,"moderation_note": string | null,"search_text": string,"slug": string,"status": Database["public"]['Enums']["series_status"],"title": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "cover_path"?: string | null,"created_at"?: string,"creator_id": string,"description"?: string,"free_chapters"?: number,"genres"?: (string)[],"hidden_by_admin"?: boolean,"id"?: string,"moderation_note"?: string | null,"search_text"?: string,"slug": string,"status"?: Database["public"]['Enums']["series_status"],"title": string,"updated_at"?: string
                  }
                  Update: {
                    "cover_path"?: string | null,"created_at"?: string,"creator_id"?: string,"description"?: string,"free_chapters"?: number,"genres"?: (string)[],"hidden_by_admin"?: boolean,"id"?: string,"moderation_note"?: string | null,"search_text"?: string,"slug"?: string,"status"?: Database["public"]['Enums']["series_status"],"title"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "series_creator_id_fkey"
      columns: ["creator_id"]
isOneToOne: false
      referencedRelation: "creators"
      referencedColumns: ["id"]
    }
                  ]
                },"subscriptions": {
                  Row: {
                    "cancel_at_period_end": boolean,"canceled_at": string | null,"created_at": string,"current_period_end": string,"current_period_start": string,"id": string,"plan_id": string | null,"provider": Database["public"]['Enums']["payment_provider"],"provider_customer_id": string | null,"provider_subscription_id": string,"status": Database["public"]['Enums']["subscription_status"],"updated_at": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "cancel_at_period_end"?: boolean,"canceled_at"?: string | null,"created_at"?: string,"current_period_end": string,"current_period_start": string,"id"?: string,"plan_id"?: string | null,"provider": Database["public"]['Enums']["payment_provider"],"provider_customer_id"?: string | null,"provider_subscription_id": string,"status": Database["public"]['Enums']["subscription_status"],"updated_at"?: string,"user_id": string
                  }
                  Update: {
                    "cancel_at_period_end"?: boolean,"canceled_at"?: string | null,"created_at"?: string,"current_period_end"?: string,"current_period_start"?: string,"id"?: string,"plan_id"?: string | null,"provider"?: Database["public"]['Enums']["payment_provider"],"provider_customer_id"?: string | null,"provider_subscription_id"?: string,"status"?: Database["public"]['Enums']["subscription_status"],"updated_at"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "subscriptions_plan_id_fkey"
      columns: ["plan_id"]
isOneToOne: false
      referencedRelation: "pricing_plans"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "subscriptions_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "apply_chapter_unlock":
{ Args: { "p_chapter": string,"p_creator": string,"p_creator_cents": number,"p_gross_cents": number,"p_period": string,"p_platform_cents": number,"p_price": number,"p_series": string,"p_share_pct": number,"p_user": string }; Returns: Json
                           },
"apply_coin_credit":
{ Args: { "p_amount": number,"p_note"?: string,"p_plan"?: string,"p_provider"?: Database["public"]['Enums']["payment_provider"],"p_ref"?: string,"p_type": Database["public"]['Enums']["coin_tx_type"],"p_user": string }; Returns: Json
                           },
"can_read_chapter":
{ Args: { "p_chapter": string }; Returns: boolean
                           },
"can_user_read_chapter":
{ Args: { "p_chapter": string,"p_user": string }; Returns: boolean
                           },
"claim_payment_event":
{ Args: { "p_event_id": string,"p_provider": string,"p_type": string }; Returns: boolean
                           },
"has_active_subscription":
{ Args: { "p_user": string }; Returns: boolean
                           },
"is_admin":
{ Args: Record<PropertyKey, never>; Returns: boolean
                           },
"is_approved_creator":
{ Args: Record<PropertyKey, never>; Returns: boolean
                           },
"owns_chapter":
{ Args: { "p_chapter": string }; Returns: boolean
                           },
"owns_series":
{ Args: { "p_series": string }; Returns: boolean
                           },
"owns_series_path":
{ Args: { "p_folder": string }; Returns: boolean
                           },
"release_payment_event":
{ Args: { "p_event_id": string,"p_provider": string }; Returns: undefined
                           },
"series_is_public":
{ Args: { "p_series": string }; Returns: boolean
                           }
          }
          Enums: {
            "chapter_access": "free"|"locked"|"early_access","coin_tx_type": "purchase"|"unlock"|"admin_grant"|"refund","creator_status": "pending"|"approved"|"rejected","earning_source": "coin_unlock"|"subscription_pool","payment_provider": "mock"|"stripe","plan_kind": "subscription"|"coin_pack","series_status": "draft"|"published","subscription_status": "active"|"canceled"|"expired"|"past_due","user_role": "reader"|"creator"|"admin"
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
  ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "graphql_public": {
          Enums: {
            
          }
        },"public": {
          Enums: {
            "chapter_access": ["free", "locked", "early_access"],"coin_tx_type": ["purchase", "unlock", "admin_grant", "refund"],"creator_status": ["pending", "approved", "rejected"],"earning_source": ["coin_unlock", "subscription_pool"],"payment_provider": ["mock", "stripe"],"plan_kind": ["subscription", "coin_pack"],"series_status": ["draft", "published"],"subscription_status": ["active", "canceled", "expired", "past_due"],"user_role": ["reader", "creator", "admin"]
          }
        }
} as const
