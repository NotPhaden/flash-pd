"use client";

import { useEffect, useMemo, useState } from "react";
import {
  Activity, BadgeCheck, BarChart3, Bell, BookOpen, Car, ChevronDown, ClipboardList, Image as ImageIcon,
  FileText, LayoutDashboard, LogOut, Menu, Search, Settings, Shield, ShieldCheck,
  Siren, Users, UserRound, X, Plus, Clock3, Award, BriefcaseBusiness, Radio,
  TrendingUp, Package, ScrollText, CalendarDays, Building2, Gavel, UserPlus
} from "lucide-react";
import { supabase } from "@/lib/supabase";
import FeatureSections from "@/components/FeatureSections";
import Policegram from "@/components/Policegram";

type Section = "Policegram" | "Dashboard" | "Personal" | "Academie" | "Notificări" | "Coduri radio" | "Modele procesări" | "Profil" | "Grade" | "Departamente" | "Logs" | "Pontaj" | "Sancțiuni" | "DCCO" | "SAS" | "Acțiuni" | "Dosare" | "Vehicule" | "Echipamente" | "Recrutări" | "Cereri concediu" | "Certificate" | "Instructori";
type Officer = { id: string; rank_level?:number; rank_id?:string|null; department_id?:string|null; department_ids?:string[]; full_name: string; badge_number: string | null; rank_name: string; department_name: string; status: string; joined_at?: string; call_sign?: string; cnp?:string|null };

async function authEmailForCharacterId(value:string) {
  const normalized=value.trim().toLowerCase();
  const bytes=new TextEncoder().encode(normalized);
  const digest=await crypto.subtle.digest("SHA-256",bytes);
  const hash=Array.from(new Uint8Array(digest)).map(b=>b.toString(16).padStart(2,"0")).join("");
  return `rp-${hash}@accounts.flash-rp.invalid`;
}
function legacyAuthEmailForCharacterId(value:string) {
  return `${value.trim().toLowerCase().replace(/[^a-z0-9._-]/g, "")}@accounts.flash-rp.invalid`;
}
const nav: { label: Section; icon: any; group: string }[] = [
  { label: "Dashboard", icon: LayoutDashboard, group: "PRINCIPAL" },
  { label: "Personal", icon: Users, group: "PRINCIPAL" },
  { label: "Academie", icon: UserPlus, group: "PRINCIPAL" },
  { label: "Certificate", icon: BadgeCheck, group: "PRINCIPAL" },
  { label: "Notificări", icon: Bell, group: "PRINCIPAL" },
  { label: "Policegram", icon: ImageIcon, group: "PRINCIPAL" },
  { label: "Coduri radio", icon: Radio, group: "RESURSE" },
  { label: "Modele procesări", icon: ScrollText, group: "RESURSE" },
  { label: "Profil", icon: UserRound, group: "SISTEM" },
  { label: "Grade", icon: Award, group: "ADMINISTRARE" },
  { label: "Departamente", icon: Building2, group: "ADMINISTRARE" },
  { label: "Logs", icon: Activity, group: "OPERAȚIONAL" },
  { label: "Instructori", icon: BadgeCheck, group: "OPERAȚIONAL" },
  { label: "Pontaj", icon: Clock3, group: "OPERAȚIONAL" },
  { label: "Cereri concediu", icon: CalendarDays, group: "OPERAȚIONAL" },
  { label: "Sancțiuni", icon: Gavel, group: "OPERAȚIONAL" },
  { label: "DCCO", icon: BriefcaseBusiness, group: "OPERAȚIONAL" },
  { label: "SAS", icon: ShieldCheck, group: "OPERAȚIONAL" },
  { label: "Acțiuni", icon: ClipboardList, group: "OPERAȚIONAL" },
  { label: "Vehicule", icon: Car, group: "RESURSE" },
  { label: "Echipamente", icon: Package, group: "RESURSE" },
  { label: "Recrutări", icon: UserPlus, group: "RESURSE" },
];


export default function Dashboard() {
  const [section, setSection] = useState<Section>("Dashboard");
  const [officers, setOfficers] = useState<Officer[]>([]);
  const [departmentCounts, setDepartmentCounts] = useState<{name:string;n:number}[]>([]);
  const [search, setSearch] = useState("");
  const [menuSearch, setMenuSearch] = useState("");
  const [modal, setModal] = useState(false);
  const [mobileNav, setMobileNav] = useState(false);
  const [userEmail, setUserEmail] = useState("Neautentificat");
  const [userRank, setUserRank] = useState("");
  const [userRankLevel, setUserRankLevel] = useState(0);
  const [sidebarAvatar, setSidebarAvatar] = useState("");
  const [userId, setUserId] = useState<string | null>(null);
  const [role, setRole] = useState("visitor");
  const [attendanceOfficer, setAttendanceOfficer] = useState("");
  const [notice, setNotice] = useState("");
  const [unreadNotifications,setUnreadNotifications]=useState(0);
  const [notificationItems,setNotificationItems]=useState<any[]>([]);
  const [notificationToast,setNotificationToast]=useState<any>(null);
  const [notificationPanel,setNotificationPanel]=useState(false);
  const [loginEmail, setLoginEmail] = useState("");
  const [authMode, setAuthMode] = useState<"login"|"register">("login");
  const [registerForm, setRegisterForm] = useState({ rp_last_name:"", rp_first_name:"", character_id:"", rp_phone:"", password:"", confirm_password:"" });
  const [loginPassword, setLoginPassword] = useState("");
  const [authLoading, setAuthLoading] = useState(true);
  const [form, setForm] = useState({ full_name: "", badge_number: "", rank_name: "Agent", department_name: "Patrulare", call_sign: "" });

  async function resolveUnitRole(uid:string, baseRole:string) {
    if (!supabase || ["super_admin","commander"].includes(baseRole)) return baseRole;
    const {data:o}:any=await supabase.from("officers").select("id,department_id,departments!officers_department_id_fkey(name),ranks!officers_rank_id_fkey(name,level)").eq("user_id",uid).maybeSingle();
    const {data:rels}=o?.id?await supabase.from("officer_departments").select("department_id,departments(name)").eq("officer_id",o.id):{data:[] as any[]};
    const names=[o?.departments?.name,...(rels||[]).map((x:any)=>x.departments?.name)].filter(Boolean).map((x:string)=>x.normalize("NFD").replace(/[\u0300-\u036f]/g,"").toLowerCase().trim());
    const rankName=String(o?.ranks?.name||"").normalize("NFD").replace(/[\u0300-\u036f]/g,"").toLowerCase().trim();
    // Gradele de conducere au prioritate: rolul se deduce și din grad, nu doar din user_roles.
    if(rankName.includes("conducere dcco") || names.includes("conducere dcco")) return "dcco_conducere";
    if(rankName.includes("conducere sas") || names.includes("conducere sas")) return "sas_conducere";
    const instructorDepartments:Record<string,string>={radio:"instructor_radio",mdt:"instructor_mdt",final:"instructor_moto",heli:"instructor_heli",hs:"instructor_hs","instructor radio":"instructor_radio","instructor mdt":"instructor_mdt","instructor final":"instructor_moto","instructor heli":"instructor_heli","instructor hs":"instructor_hs"};
    for (const [department, instructorRole] of Object.entries(instructorDepartments)) if (names.includes(department)) return instructorRole;
    if(rankName.includes("instructor radio")) return "instructor_radio";
    if(rankName.includes("instructor mdt")) return "instructor_mdt";
    if(rankName.includes("instructor heli")) return "instructor_heli";
    if(rankName.includes("instructor moto")) return "instructor_moto";
    if(rankName.includes("instructor hs")) return "instructor_hs";
    if(names.includes("dcco")) return rankName.includes("conducere dcco")?"dcco_conducere":"dcco";
    if(names.includes("sas")) return rankName.includes("conducere sas")?"sas_conducere":"sas";
    // user_roles rămâne adesea "visitor" după ce conducerea atribuie gradul din site.
    // Gradul din officers.ranks este sursa efectivă pentru accesul operațional.
    if(rankName && !["vizitator","visitor","academie"].includes(rankName)) return baseRole === "visitor" ? "officer" : baseRole;
    return baseRole;
  }

  useEffect(() => {
    const client = supabase;
    if (!client) { setAuthLoading(false); return; }
    client.auth.getSession().then(async ({ data }) => {
      setAuthLoading(false);
      const authUser = data.session?.user;
      if (!authUser) { setUserId(null); setUserEmail("Neautentificat"); setOfficers([]); return; }
      setUserEmail(String([authUser.user_metadata?.rp_first_name,authUser.user_metadata?.rp_last_name].filter(Boolean).join(" ") || authUser.user_metadata?.full_name || "Cont autentificat")); setUserId(authUser.id);
      const { data: roleData } = await client.from("user_roles").select("role").eq("user_id", authUser.id).maybeSingle();
      const resolved=await resolveUnitRole(authUser.id,roleData?.role||"visitor"); setRole(resolved);
      const {data:rankRow}:any=await client.from("officers").select("avatar_url,ranks(name,level)").eq("user_id",authUser.id).maybeSingle();
      const rankName=String(rankRow?.ranks?.name||"").trim().toLowerCase();
      setUserRank(rankRow?.ranks?.name||"Grad neatribuit");setUserRankLevel(Number(rankRow?.ranks?.level||0));setSidebarAvatar(rankRow?.avatar_url||"");
      if(resolved==="visitor" || rankName==="academie")setSection("Academie");
    });
    const authSub = client.auth.onAuthStateChange((_event, session) => {
      setUserId(session?.user.id || null); setUserEmail(String([session?.user.user_metadata?.rp_first_name,session?.user.user_metadata?.rp_last_name].filter(Boolean).join(" ") || session?.user.user_metadata?.full_name || "Neautentificat"));
      if (!session?.user) { setOfficers([]); setRole("visitor"); }
      else {
        loadOfficers();
        setTimeout(async () => { const {data}=await client.from("user_roles").select("role").eq("user_id", session.user.id).maybeSingle(); const resolved=await resolveUnitRole(session.user.id,data?.role||"visitor"); setRole(resolved); const {data:rankRow}:any=await client.from("officers").select("avatar_url,ranks(name,level)").eq("user_id",session.user.id).maybeSingle(); setUserRank(rankRow?.ranks?.name||"Grad neatribuit");setUserRankLevel(Number(rankRow?.ranks?.level||0));setSidebarAvatar(rankRow?.avatar_url||""); }, 0);
      }
    });
    const refreshCurrentAccount = async (uid:string) => {
      const {data:rr}=await client.from("user_roles").select("role").eq("user_id",uid).maybeSingle();
      const resolved=await resolveUnitRole(uid,rr?.role||"visitor");
      const {data:rankRow}:any=await client.from("officers").select("avatar_url,ranks(name,level)").eq("user_id",uid).maybeSingle();
      setRole(resolved);
      setUserRank(rankRow?.ranks?.name||"Grad neatribuit");
      setUserRankLevel(Number(rankRow?.ranks?.level||0));
      setSidebarAvatar(rankRow?.avatar_url||"");
      if(resolved==="visitor" || String(rankRow?.ranks?.name||"").toLowerCase()==="academie")setSection("Academie");
    };
    const channel = client.channel("officer-changes").on("postgres_changes",
      { event: "*", schema: "public", table: "officers" }, async (payload:any) => {
        loadOfficers();
        const {data:sessionData}=await client.auth.getSession();
        const uid=sessionData.session?.user.id;
        if(uid && (payload.new?.user_id===uid || payload.old?.user_id===uid)) await refreshCurrentAccount(uid);
      }).subscribe();
    // A rank's label/level can change without touching officers.rank_id. Subscribe to
    // the referenced table as well so the dashboard never keeps a stale joined rank.
    const rankChannel = client.channel("rank-catalog-changes").on("postgres_changes",
      { event: "*", schema: "public", table: "ranks" }, async () => {
        loadOfficers();
        const {data:sessionData}=await client.auth.getSession();
        const uid=sessionData.session?.user.id;
        if(uid) await refreshCurrentAccount(uid);
      }).subscribe();
    const roleChannel = client.channel("user-role-changes").on("postgres_changes",
      { event: "*", schema: "public", table: "user_roles" }, async (payload:any) => {
        const {data:sessionData}=await client.auth.getSession();
        const uid=sessionData.session?.user.id;
        if(uid && (payload.new?.user_id===uid || payload.old?.user_id===uid)) await refreshCurrentAccount(uid);
      }).subscribe();
    loadOfficers();
    return () => {
      client.removeChannel(channel);
      client.removeChannel(rankChannel);
      client.removeChannel(roleChannel);
      authSub.data.subscription.unsubscribe();
    };
  }, []);

  useEffect(() => {
    if (!supabase || !userId) { setUserRank(""); setUserRankLevel(0); return; }
    supabase.from("officers").select("ranks(name,level)").eq("user_id", userId).maybeSingle().then(({ data }: any) => {
      const resolvedRank=data?.ranks?.name || "Grad neatribuit";
      setUserRank(resolvedRank);
      setUserRankLevel(Number(data?.ranks?.level || 0));
      if (String(resolvedRank).trim().toLowerCase()==="academie") setSection("Academie");
    });
  }, [userId, role]);

  async function loadOfficers() {
    if (!supabase) { setOfficers([]); return; }
    const { data, error } = await supabase.from("officers")
      .select("id,user_id,rank_id,department_id,full_name,badge_number,status,joined_at,call_sign,cnp,ranks!officers_rank_id_fkey(name,level),departments!officers_department_id_fkey(name)")
      .order("created_at", { ascending: false });
    if (error) { setNotice("Nu am putut încărca personalul: " + error.message); return; }
    if (data) {
      const {data: memberships} = await supabase.from("officer_departments").select("officer_id,department_id,departments(name)");
      const userIds=data.map((o:any)=>o.user_id).filter(Boolean);
      const {data:rpAccounts}=userIds.length?await supabase.from("rp_accounts").select("user_id,character_id,rp_first_name,rp_last_name").in("user_id",userIds):{data:[] as any[]};
      const mapped = data.map((o: any) => {
        const rp=(rpAccounts||[]).find((x:any)=>x.user_id===o.user_id);
        const rels=(memberships||[]).filter((m:any)=>m.officer_id===o.id);
        const ids=Array.from(new Set([...rels.map((m:any)=>m.department_id),...(o.department_id?[o.department_id]:[])]));
        const names=Array.from(new Set([...rels.map((m:any)=>m.departments?.name).filter(Boolean),...(o.departments?.name?[o.departments.name]:[])]));
        return { id:o.id,rank_id:o.rank_id,department_id:o.department_id,department_ids:ids,full_name:o.full_name,badge_number:o.badge_number,
          rank_name:o.ranks?.name||"Nesetat",department_name:names.join(", ")||"Nesetat",status:o.status||"Activ",joined_at:o.joined_at,call_sign:o.call_sign,cnp:o.cnp||rp?.character_id||null,rank_level:Number(o.ranks?.level||0) };
      });
      setOfficers(mapped);
      const {data:allDepartments}=await supabase.from("departments").select("id,name").order("name");
      setDepartmentCounts((allDepartments||[]).filter((d:any)=>!["intervenții speciale","criminalistică","intervenții criminale","ordine publică","poliția rutieră","poliție rutieră"].includes(String(d.name).toLocaleLowerCase("ro-RO"))).map((d:any)=>({name:d.name,n:d.name.toLowerCase()==="conducere"?mapped.filter((o:any)=>o.rank_level>=8&&o.rank_level<=13).length:mapped.filter((o:Officer)=>(o.department_ids||[]).includes(d.id)).length})));
    }
  }


  async function addOfficer(e: React.FormEvent) {
    e.preventDefault();
    if (!userId) { setNotice("Autentifică-te cu un cont real pentru a administra personalul."); return; }
    if (!form.full_name.trim() || !form.badge_number.trim()) return;
    if (!supabase) { setNotice("Serviciul de date nu este disponibil momentan. Încearcă din nou mai târziu."); return; }
    const { data: rank } = await supabase.from("ranks").select("id").eq("name", form.rank_name).maybeSingle();
    const { data: dept } = await supabase.from("departments").select("id").eq("name", form.department_name).maybeSingle();
    const { error } = await supabase.from("officers").insert({
      full_name: form.full_name, badge_number: form.badge_number,
      rank_id: rank?.id ?? null, department_id: dept?.id ?? null, call_sign: form.call_sign || null, status: "Activ"
    });
    if (error) setNotice("Eroare la salvare: " + error.message);
    else { setNotice("Polițist adăugat cu succes."); await loadOfficers(); setModal(false); setForm({ full_name: "", badge_number: "", rank_name: "Agent", department_name: "Ordine publică", call_sign: "" }); }
  }

  async function signIn(e: React.FormEvent) {
    e.preventDefault();
    if (!supabase) { setNotice("Autentificarea nu este disponibilă momentan."); return; }
    setAuthLoading(true);
    const characterId = loginEmail.trim().toLowerCase();
    const legacyEmail=legacyAuthEmailForCharacterId(characterId);
    const { error:legacyError } = await supabase.auth.signInWithPassword({ email: legacyEmail, password: loginPassword });
    if (legacyError) {
      const hashedEmail=await authEmailForCharacterId(characterId);
      const {error}=await supabase.auth.signInWithPassword({email:hashedEmail,password:loginPassword});
      setAuthLoading(false);
      if(error)setNotice("Autentificare nereușită: verifică ID-ul și parola.");
      return;
    }
    setAuthLoading(false);
  }

  async function signUp(e: React.FormEvent) {
    e.preventDefault();
    if (!supabase) { setNotice("Înregistrarea nu este disponibilă momentan."); return; }
    const f = registerForm;
    const characterId = f.character_id.trim().toLowerCase();
    if (!/^[a-z0-9._-]+$/.test(characterId)) { setNotice("ID-ul poate conține doar litere, cifre, punct, _ sau -."); return; }
    if (f.password.length < 8) { setNotice("Parola trebuie să aibă minimum 8 caractere."); return; }
    if (f.password !== f.confirm_password) { setNotice("Parolele nu coincid."); return; }
    if (!f.rp_last_name.trim() || !f.rp_first_name.trim() || !f.rp_phone.trim()) { setNotice("Completează toate câmpurile RP."); return; }
    setAuthLoading(true);
    const authEmail = await authEmailForCharacterId(characterId);
    const { error } = await supabase.auth.signUp({
      email: authEmail, password: f.password,
      options: { data: { character_id: characterId, rp_first_name: f.rp_first_name.trim(), rp_last_name: f.rp_last_name.trim(), rp_phone: f.rp_phone.trim() } }
    });
    setAuthLoading(false);
    if (error) { setNotice("Înregistrare nereușită: " + error.message); return; }
    setNotice("Cont creat. Te poți autentifica folosind ID-ul personajului și parola.");
    setAuthMode("login"); setLoginEmail(characterId); setLoginPassword("");
  }

  async function signOut() {
    if (supabase) await supabase.auth.signOut();
    setUserEmail("Neautentificat"); setUserId(null); setOfficers([]);
    setNotice("Sesiunea a fost închisă.");
  }

  const filtered = useMemo(() => officers.filter(o => `${o.full_name} ${o.badge_number} ${o.rank_name} ${o.department_name}`.toLowerCase().includes(search.toLowerCase())), [officers, search]);
  const [activeCount, setActiveCount] = useState(0);
  useEffect(() => { if (!supabase || !userId) { setActiveCount(0); return; } supabase.from("attendance").select("id", { count: "exact", head: true }).is("shift_end", null).then(({ count, error }) => { if (!error) setActiveCount(count || 0); }); }, [userId, officers]);
  useEffect(()=>{if(!supabase||!userId){setUnreadNotifications(0);return;}const client=supabase;let alive=true;let newestSeen="";const refresh=async(showNew=false)=>{const {data,count,error}=await client.from("notifications").select("id,title,message,created_at,read_at",{count:"exact"}).eq("user_id",userId).order("created_at",{ascending:false}).limit(30);if(!alive||error)return;setNotificationItems((data||[]).slice(0,8));setUnreadNotifications((data||[]).filter((n:any)=>!n.read_at).length);const latest=(data||[])[0];if(showNew&&latest&&latest.id!==newestSeen){newestSeen=latest.id;if(!latest.read_at){setNotificationToast(latest);try{const Ctx=(window as any).AudioContext||(window as any).webkitAudioContext;if(Ctx){const ctx=new Ctx(),osc=ctx.createOscillator(),gain=ctx.createGain();osc.type="sine";osc.frequency.value=880;gain.gain.value=0.05;osc.connect(gain);gain.connect(ctx.destination);osc.start();osc.stop(ctx.currentTime+0.2);osc.onended=()=>ctx.close();}}catch{}}}else if(latest&&!newestSeen)newestSeen=latest.id;};refresh(false);const channel=client.channel(`notifications-${userId}`).on("postgres_changes",{event:"INSERT",schema:"public",table:"notifications",filter:`user_id=eq.${userId}`},(payload:any)=>{const n=payload.new;newestSeen=n.id;setUnreadNotifications(v=>v+1);setNotificationToast(n);try{const Ctx=(window as any).AudioContext||(window as any).webkitAudioContext;if(Ctx){const ctx=new Ctx(),osc=ctx.createOscillator(),gain=ctx.createGain();osc.type="sine";osc.frequency.value=880;gain.gain.value=0.05;osc.connect(gain);gain.connect(ctx.destination);osc.start();osc.stop(ctx.currentTime+0.2);osc.onended=()=>ctx.close();}}catch{}}).on("postgres_changes",{event:"UPDATE",schema:"public",table:"notifications",filter:`user_id=eq.${userId}`},()=>refresh(false)).subscribe();const poll=window.setInterval(()=>refresh(true),12000);return()=>{alive=false;window.clearInterval(poll);client.removeChannel(channel)}},[userId]);

  if (!userId) return <div className="min-h-screen bg-[#0b0e13] flex items-center justify-center p-4"><div className="panel w-full max-w-md p-7"><div className="mb-6"><div className="text-xl font-black"><span className="text-blue-400">FLASH</span> · Cont RP</div><p className="muted mt-2 text-sm">Autentificare cu ID fictiv de personaj FiveM. Nu este necesar un email real.</p></div>
    <div className="grid grid-cols-2 gap-2 mb-5"><button type="button" onClick={()=>{setAuthMode("login");setNotice("");}} className={`btn ${authMode==="login"?"btn-primary":"btn"}`}>Autentificare</button><button type="button" onClick={()=>{setAuthMode("register");setNotice("");}} className={`btn ${authMode==="register"?"btn-primary":"btn"}`}>Înregistrare</button></div>
    {authMode==="login" ? <form onSubmit={signIn}><label className="block text-sm mb-4">ID personaj / CNP fictiv<input required className="field mt-2" autoComplete="username" value={loginEmail} onChange={e=>setLoginEmail(e.target.value)} placeholder="ex. LSPD-1042"/></label><label className="block text-sm mb-5">Parolă<input type="password" required className="field mt-2" autoComplete="current-password" value={loginPassword} onChange={e=>setLoginPassword(e.target.value)}/></label><button disabled={authLoading} className="btn btn-primary w-full">{authLoading ? "Se verifică..." : "Autentificare"}</button></form> :
    <form onSubmit={signUp} className="space-y-3"><label className="block text-sm">Nume RP<input required className="field mt-1" value={registerForm.rp_last_name} onChange={e=>setRegisterForm({...registerForm,rp_last_name:e.target.value})}/></label><label className="block text-sm">Prenume RP<input required className="field mt-1" value={registerForm.rp_first_name} onChange={e=>setRegisterForm({...registerForm,rp_first_name:e.target.value})}/></label><label className="block text-sm">CNP fictiv / ID personaj FiveM<input required className="field mt-1" value={registerForm.character_id} onChange={e=>setRegisterForm({...registerForm,character_id:e.target.value})} placeholder="ex. LSPD-1042"/></label><label className="block text-sm">Telefon fictiv RP<input required className="field mt-1" value={registerForm.rp_phone} onChange={e=>setRegisterForm({...registerForm,rp_phone:e.target.value})} placeholder="555-0104"/></label><label className="block text-sm">Parolă<input type="password" minLength={8} required className="field mt-1" value={registerForm.password} onChange={e=>setRegisterForm({...registerForm,password:e.target.value})}/></label><label className="block text-sm">Confirmă parola<input type="password" minLength={8} required className="field mt-1" value={registerForm.confirm_password} onChange={e=>setRegisterForm({...registerForm,confirm_password:e.target.value})}/></label><button disabled={authLoading} className="btn btn-primary w-full">{authLoading?"Se creează contul...":"Creează cont RP"}</button></form>}
    {notice&&<p className="mt-4 text-sm text-amber-300">{notice}</p>}<p className="muted mt-5 text-xs">Conturile noi primesc doar rolul de bază. Gradul, departamentul, call sign-ul și permisiunile sunt stabilite exclusiv de conducere.</p></div></div>;

  return (
    <div className="min-h-screen bg-[#0b0e13]">
      <aside className={`fixed inset-y-0 left-0 z-40 flex w-[248px] flex-col border-r border-[#252d37] bg-[#10151c] transition-transform lg:translate-x-0 ${mobileNav ? "translate-x-0" : "-translate-x-full"}`}>
        <div className="flex h-[72px] items-center gap-3 border-b border-[#252d37] px-5">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-blue-500/15 text-blue-400"><Shield size={23}/></div>
          <div><div className="text-sm font-black tracking-wide"><span className="text-blue-400">FLASH</span></div><div className="label mt-1">Management system</div></div>
          <button className="ml-auto text-slate-400 lg:hidden" onClick={() => setMobileNav(false)}><X size={19}/></button>
        </div>
        <div className="px-4 py-4"><div className="flex items-center gap-2 rounded-xl border border-[#2b3541] bg-[#0c1117] px-3 py-2"><Search size={14} className="shrink-0 text-slate-500"/><input aria-label="Caută în meniu" placeholder="Caută în meniu..." value={menuSearch} onChange={e=>setMenuSearch(e.target.value)} className="min-w-0 flex-1 bg-transparent text-xs text-slate-200 outline-none placeholder:text-slate-500"/>{menuSearch&&<button aria-label="Șterge căutarea" onClick={()=>setMenuSearch("")} className="text-slate-500"><X size={13}/></button>}<span className="rounded bg-[#252d37] px-1.5 py-0.5 text-[9px] text-slate-400">⌘ K</span></div></div>
        <nav className="flex-1 overflow-y-auto px-3 pb-5">
          {["PRINCIPAL", "ADMINISTRARE", "OPERAȚIONAL", "RESURSE", "SISTEM"].map(group => (
            <div key={group} className="mb-5">
              <div className="label mb-2 px-3">{group}</div>
              {nav.filter(n => n.group === group && n.label.toLocaleLowerCase("ro-RO").includes(menuSearch.trim().toLocaleLowerCase("ro-RO")) && (role !== "visitor" || ["Academie","Profil","Notificări","Policegram"].includes(n.label)) && (userRank.toLowerCase() !== "academie" || ["Academie","Profil","Notificări","Policegram"].includes(n.label)) && (n.label !== "Instructori" || ["instructor_radio","instructor_mdt","instructor_heli","instructor_moto","instructor_hs","super_admin","commander"].includes(role) || userRankLevel >= 8) && (n.label !== "DCCO" || ["super_admin","commander","dcco","dcco_conducere"].includes(role) || userRank.toLowerCase().includes("conducere dcco")) && (n.label !== "SAS" || ["super_admin","commander","sas","sas_conducere"].includes(role) || userRank.toLowerCase().includes("conducere sas")) && (n.label !== "Recrutări" || (userRankLevel >= 8 && userRankLevel <= 13) || ["super_admin","commander"].includes(role)) && (n.label !== "Logs" || (userRankLevel >= 8 && userRankLevel <= 13) || ["super_admin","commander"].includes(role))).map(item => {
                const Icon = item.icon; const selected = section === item.label;
                return <button key={item.label} onClick={() => { setSection(item.label); setMobileNav(false); }} className={`mb-1 flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-left text-[13px] font-semibold transition ${selected ? "bg-blue-500/15 text-blue-300" : "text-slate-400 hover:bg-white/5 hover:text-slate-100"}`}>
                  <Icon size={16}/>{item.label}{item.label === "Dashboard" && <span className="ml-auto rounded-full bg-emerald-500/15 px-2 py-0.5 text-[9px] font-black text-emerald-400">LIVE</span>}
                </button>;
              })}
            </div>
          ))}
        </nav>
        <div className="border-t border-[#252d37] p-4">
          <div className="flex items-center gap-3 rounded-xl bg-[#1a222c] p-3">
            <div className="flex h-9 w-9 items-center justify-center overflow-hidden rounded-full bg-blue-500/20 text-blue-300">{sidebarAvatar?<img src={sidebarAvatar} alt="Avatar" className="h-full w-full object-cover"/>:<UserRound size={17}/>}</div>
            <div className="min-w-0 flex-1"><div className="truncate text-xs font-bold">{userEmail}</div><div className="label mt-1">{userRank || ({super_admin:"Chestor general",commander:"Chestor secundar",hr:"Resurse umane",officer:"Grad neatribuit",visitor:"Vizitator",instructor_radio:"Instructor Radio",instructor_mdt:"Instructor MDT",instructor_heli:"Instructor Heli",instructor_moto:"Instructor Moto",instructor_hs:"Instructor HS",dcco:"DCCO",dcco_conducere:"Conducere DCCO",sas:"SAS",sas_conducere:"Conducere SAS"} as Record<string,string>)[role] || "Grad neatribuit"}</div></div>
            <button onClick={signOut} title="Ieșire" className="text-slate-500 hover:text-white"><LogOut size={16}/></button>
          </div>
        </div>
      </aside>

      {mobileNav && <button aria-label="Închide meniul" onClick={() => setMobileNav(false)} className="fixed inset-0 z-30 bg-black/60 lg:hidden"/>}
      <main className="min-h-screen lg:ml-[248px]">
        <header className="sticky top-0 z-20 flex h-[72px] items-center justify-between border-b border-[#252d37] bg-[#0b0e13]/90 px-4 backdrop-blur-xl sm:px-7">
          <div className="flex items-center gap-3"><button className="text-slate-400 lg:hidden" onClick={() => setMobileNav(true)}><Menu/></button><div className="hidden text-xs text-slate-500 sm:block">FLASH <span className="mx-2">/</span><span className="text-slate-200">{section}</span></div><div className="text-sm font-bold sm:hidden">{section}</div></div>
          <div className="flex items-center gap-2"><button onClick={() => setNotificationPanel(v=>!v)} aria-label="Deschide notificările" className={`relative rounded-lg border p-2 text-slate-200 ${unreadNotifications>0?"border-amber-400 bg-amber-400/10 animate-pulse":"border-[#29313b]"}`}><Bell size={17}/>{unreadNotifications>0&&<span className="absolute -right-1 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full bg-red-500 px-1 text-[9px] font-black text-white">{unreadNotifications>9?"9+":unreadNotifications}</span>}</button></div>
        </header>
        {notificationPanel&&<div className="absolute right-4 top-[78px] z-40 w-[min(92vw,420px)] rounded-2xl border border-slate-700 bg-[#151b23] p-4 shadow-2xl"><div className="flex items-center justify-between"><b>Notificări</b><button className="text-slate-400" onClick={()=>setNotificationPanel(false)}><X size={16}/></button></div><p className="muted mt-1 text-xs">{unreadNotifications} necitite</p><div className="mt-3 max-h-80 space-y-2 overflow-y-auto">{notificationItems.map((n:any)=><button key={n.id} onClick={async()=>{if(supabase&&!n.read_at)await supabase.from("notifications").update({read_at:new Date().toISOString()}).eq("id",n.id);setNotificationPanel(false);setNotificationToast(null);setSection("Notificări");}} className={`block w-full rounded-xl border p-3 text-left ${n.read_at?"border-slate-700 bg-slate-900/30":"border-blue-400/40 bg-blue-500/10"}`}><span className="block text-sm font-bold">{n.title||"Notificare"}</span><span className="mt-1 block text-xs text-slate-300">{n.message||""}</span><span className="mt-2 block text-[10px] text-slate-500">{n.created_at?new Date(n.created_at).toLocaleString("ro-RO"):""}</span></button>)}{!notificationItems.length&&<p className="py-4 text-sm text-slate-400">Nu ai notificări.</p>}</div><button className="btn btn-primary mt-3 w-full" onClick={()=>{setNotificationPanel(false);setSection("Notificări")}}>Deschide toate notificările</button></div>}
        {notificationToast&&<div role="alert" className="fixed right-5 top-20 z-[70] w-[min(92vw,390px)] rounded-2xl border border-blue-400/40 bg-[#172333] p-4 shadow-2xl"><div className="flex items-start gap-3"><span className="rounded-xl bg-blue-500/20 p-2 text-blue-300"><Bell size={18}/></span><div className="min-w-0 flex-1"><b className="block">{notificationToast.title||"Notificare nouă"}</b><p className="mt-1 text-sm text-slate-300">{notificationToast.message}</p><button className="mt-3 text-xs font-bold text-blue-300" onClick={async()=>{if(supabase&&notificationToast?.id)await supabase.from("notifications").update({read_at:new Date().toISOString()}).eq("id",notificationToast.id);setSection("Notificări");setNotificationToast(null);}}>Vezi notificarea</button></div><button className="text-slate-400" onClick={()=>setNotificationToast(null)}><X size={15}/></button></div></div>}

        <div className="mx-auto max-w-[1600px] p-4 sm:p-7">
          {notice && <div className="mb-5 flex items-start justify-between gap-3 rounded-xl border border-blue-500/20 bg-blue-500/10 px-4 py-3 text-sm text-blue-200"><span>{notice}</span><button onClick={() => setNotice("")}><X size={16}/></button></div>}
          {section === "Policegram" ? <Policegram userId={userId} onNotice={setNotice} role={role} rankLevel={userRankLevel}/> : (role === "visitor" || userRank.toLowerCase()==="academie") && !["Academie","Profil","Notificări","Policegram"].includes(section) ? <div className="panel p-6"><h1 className="text-xl font-black">Acces limitat · Vizitator</h1><p className="muted mt-2 text-sm">Contul de vizitator poate consulta doar Academia, profilul și notificările.</p></div> : section === "Dashboard" ? <DashboardHome officers={officers} activeCount={activeCount} departmentCounts={departmentCounts} canViewAudit={userRankLevel>=8||["super_admin","commander"].includes(role)} onNavigate={setSection}/> :
            section === "Personal" ? <Personnel officers={filtered} search={search} setSearch={setSearch} onAdd={() => setModal(true)} role={role} rankLevel={userRankLevel} onRefresh={loadOfficers} onViewAttendance={(id:string)=>{setAttendanceOfficer(id);setSection("Pontaj");}}/> :
            ["Academie","Certificate","Notificări","Coduri radio","Modele procesări","Profil","Pontaj","Sancțiuni","DCCO","SAS","Acțiuni","Recrutări","Logs","Instructori","Cereri concediu"].includes(section) ? <FeatureSections section={section === "Recrutări" ? "Recrutări" : section} officers={officers} userId={userId} role={role} rankLevel={userRankLevel} initialTarget={attendanceOfficer} onNotice={setNotice} onProfileUpdate={(url:string)=>setSidebarAvatar(url)}/> :
            <GenericSection section={section} officers={officers} onAdd={() => setModal(true)} role={role} rankLevel={userRankLevel}/>}
        </div>
      </main>

      {modal && <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4" onMouseDown={e => { if (e.target === e.currentTarget) setModal(false); }}>
        <form onSubmit={addOfficer} className="panel w-full max-w-lg p-6 shadow-2xl">
          <div className="mb-5 flex items-center justify-between"><div><div className="text-lg font-black">Adaugă polițist</div><div className="muted mt-1 text-xs">Completează datele de înregistrare.</div></div><button type="button" onClick={() => setModal(false)} className="text-slate-400"><X/></button></div>
          <div className="grid gap-4 sm:grid-cols-2">
            <label className="text-xs font-bold text-slate-400 sm:col-span-2">Nume complet<input required className="field mt-2" value={form.full_name} onChange={e => setForm({...form, full_name:e.target.value})} placeholder="Ex: Andrei Popescu"/></label>
            <label className="text-xs font-bold text-slate-400">Număr legitimație<input required className="field mt-2" value={form.badge_number} onChange={e => setForm({...form, badge_number:e.target.value})} placeholder="Ex: 042"/></label>
            <label className="text-xs font-bold text-slate-400">Grad<select className="field mt-2" value={form.rank_name} onChange={e => setForm({...form, rank_name:e.target.value})}>{["Vizitator","Agent","Agent principal","Agent șef adjunct","Agent șef","Subinspector","Inspector","Inspector principal","Subcomisar","Comisar","Comisar-șef","Chestor secundar","Chestor general"].map(x=><option key={x}>{x}</option>)}</select></label>
            <label className="text-xs font-bold text-slate-400 sm:col-span-2">Call sign<input className="field mt-2" value={form.call_sign} onChange={e => setForm({...form,call_sign:e.target.value})} placeholder="Ex: 1-Adam-01"/></label>
            <label className="text-xs font-bold text-slate-400 sm:col-span-2">Departament<select className="field mt-2" value={form.department_name} onChange={e => setForm({...form, department_name:e.target.value})}>{["Conducere","DCCO","SAS","Patrulare","Academie"].map(x=><option key={x}>{x}</option>)}</select></label>
          </div>
          <div className="mt-6 flex justify-end gap-2"><button type="button" className="btn" onClick={() => setModal(false)}>Anulează</button><button className="btn btn-primary" type="submit"><Plus size={15}/> Salvează polițist</button></div>
        </form>
      </div>}
    </div>
  );
}

function DashboardHome({ officers, activeCount, departmentCounts, canViewAudit, onNavigate }: { officers: Officer[]; activeCount: number; departmentCounts:{name:string;n:number}[]; canViewAudit:boolean; onNavigate: (s: Section) => void }) {
  const stats = [
    { label:"Personal înregistrat", value:officers.length, detail:"În baza de date", icon:Users, color:"text-blue-400", bg:"bg-blue-500/10" },
    { label:"Polițiști activi", value:activeCount, detail:"Pontaje în desfășurare", icon:ShieldCheck, color:"text-emerald-400", bg:"bg-emerald-500/10" },
    { label:"Departamente", value:departmentCounts.length, detail:"Structuri cu personal", icon:Building2, color:"text-violet-400", bg:"bg-violet-500/10" },
  ];
  return <div className="space-y-7">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><div className="label mb-2">CENTRALĂ OPERAȚIONALĂ</div><h1 className="text-2xl font-black tracking-tight sm:text-3xl">Bun venit în <span className="text-blue-400">Police HQ</span></h1><p className="muted mt-2 text-sm">Panoul central de administrare al departamentului.</p></div>{canViewAudit&&<div className="flex gap-2"><button onClick={() => onNavigate("Logs")} className="btn"><Activity size={15}/> Logs</button></div>}</div>
    <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">{stats.map(s=>{const Icon=s.icon;return <div key={s.label} className="panel p-5"><div className="flex items-center justify-between"><span className="label">{s.label}</span><span className={`rounded-xl p-2.5 ${s.bg} ${s.color}`}><Icon size={19}/></span></div><div className="mt-5 text-3xl font-black">{s.value}</div><div className="muted mt-1 text-xs">{s.detail}</div></div>})}</div>
    <div className="grid gap-5">
      <div className="panel p-5 sm:p-6"><div className="mb-5 flex items-center justify-between"><h2 className="font-extrabold">Structuri departamentale</h2><button onClick={()=>onNavigate("Departamente")} className="text-xs font-bold text-blue-400">Vezi toate</button></div>{departmentCounts.map(d=><div key={d.name} className="mb-5"><div className="mb-2 flex justify-between text-xs"><span className="font-semibold">{d.name}</span><span className="muted">{d.n} membri</span></div><div className="h-1.5 overflow-hidden rounded-full bg-[#29313b]"><div className="h-full rounded-full bg-blue-400" style={{width:`${officers.length?d.n/officers.length*100:0}%`}}/></div></div>)}{!departmentCounts.length&&<p className="muted text-sm">Nu există departamente atribuite personalului.</p>}</div>
    </div>
    <div className="panel overflow-hidden"><div className="flex items-center justify-between p-5"><div><h2 className="font-extrabold">Personal recent</h2><p className="muted mt-1 text-xs">Ultimii polițiști înregistrați</p></div><button onClick={()=>onNavigate("Personal")} className="text-xs font-bold text-blue-400">Deschide registrul →</button></div><OfficerTable officers={officers.slice(0,5)}/></div>
    <div className="grid gap-4 sm:grid-cols-3">{canViewAudit&&<><QuickCard icon={Radio} title="Logs" desc="Evenimente administrative" onClick={()=>onNavigate("Logs")}/><QuickCard icon={ScrollText} title="Rapoarte" desc="Documente și rapoarte de serviciu" onClick={()=>onNavigate("Logs")}/></>}<QuickCard icon={BadgeCheck} title="Grade & promovări" desc="Ierarhie și carieră profesională" onClick={()=>onNavigate("Grade")}/></div>
  </div>;
}

function Personnel({ officers, search, setSearch, onAdd, role, rankLevel, onRefresh, onViewAttendance }: { officers: Officer[]; search: string; setSearch: (s:string)=>void; onAdd:()=>void; role:string; rankLevel:number; onRefresh:()=>void; onViewAttendance:(id:string)=>void }) {
  const [ranks,setRanks]=useState<any[]>([]),[departments,setDepartments]=useState<any[]>([]),[editing,setEditing]=useState<Officer|null>(null),[draft,setDraft]=useState<any>({}),[certificates,setCertificates]=useState<string[]>([]),[promotionLog,setPromotionLog]=useState<any[]>([]);
  const canEdit=(rankLevel>=8&&rankLevel<=13)||["super_admin","commander"].includes(role);
  const canAssignRank=(rankLevel>=12&&rankLevel<=13)||["super_admin","commander"].includes(role);
  useEffect(()=>{if(!supabase||!canEdit)return;Promise.all([supabase.from("ranks").select("id,name").order("level"),supabase.from("departments").select("id,name").order("name")]).then(([r,d])=>{setRanks((r.data||[]).filter((x:any)=>!/^conducere\s+(sas|dcco)$/i.test(String(x.name||"").trim())));setDepartments((d.data||[]).filter((x:any)=>!["intervenții speciale","criminalistică","intervenții criminale","ordine publică","poliția rutieră","poliție rutieră"].includes(String(x.name).toLocaleLowerCase("ro-RO"))));});},[canEdit]);
  async function openEdit(o:Officer){let ids=o.department_ids||[];if(supabase){const {data}=await supabase.from("officer_departments").select("department_id").eq("officer_id",o.id);if(data?.length)ids=data.map((x:any)=>x.department_id);}setEditing(o);setDraft({full_name:o.full_name,cnp:o.cnp||"",call_sign:o.call_sign||"",rank_id:o.rank_id||"",department_ids:ids,badge_number:o.badge_number||"",status:o.status||"Activ",joined_at:o.joined_at||new Date().toISOString().slice(0,10)});
    if(supabase){const [c,l]=await Promise.all([supabase.from("officer_certificates").select("certificate").eq("officer_id",o.id),supabase.from("officer_promotions").select("id,change_type,old_rank_name,new_rank_name,created_at").eq("officer_id",o.id).order("created_at",{ascending:false})]);setCertificates((c.data||[]).map((x:any)=>x.certificate));setPromotionLog(l.data||[]);}}
  async function saveEdit(e:React.FormEvent){
    e.preventDefault();
    if(!supabase||!editing||!canEdit)return;
    const {error}=await supabase.rpc("save_officer_record_with_career",{
      p_officer_id:editing.id,
      p_full_name:draft.full_name.trim(),
      p_cnp:draft.cnp.trim()||null,
      p_call_sign:draft.call_sign.trim()||null,
      p_badge_number:draft.badge_number.trim()||null,
      p_status:draft.status,
      p_joined_at:draft.joined_at||null,
      p_update_assignments:canAssignRank,
      p_rank_id:canAssignRank?(draft.rank_id||null):null,
      p_department_ids:canAssignRank?(draft.department_ids||[]):[]
    });
    if(error){alert("Nu s-au putut salva datele membrului: "+error.message);return;}
    if(canAssignRank){
      for(const cert of ["Radio","MDT","Heli","Moto","HS"]){
        if(certificates.includes(cert)) { const {error:e}=await supabase.from("officer_certificates").upsert({officer_id:editing.id,certificate:cert},{onConflict:"officer_id,certificate"}); if(e){alert("Eroare la acordarea certificatului "+cert+": "+e.message);return;} }
        else { const {error:e}=await supabase.from("officer_certificates").delete().eq("officer_id",editing.id).eq("certificate",cert); if(e){alert("Eroare la eliminarea certificatului "+cert+": "+e.message);return;} }
      }
    }
    setEditing(null);onRefresh();
  }
  return <div className="space-y-6"><div className="flex flex-wrap items-end justify-between gap-4"><div><div className="label mb-2">RESURSE UMANE</div><h1 className="text-3xl font-black">Registru personal</h1><p className="muted mt-2 text-sm">Administrarea polițiștilor și a informațiilor profesionale.</p></div></div>
    <div className="grid gap-3 sm:grid-cols-3"><MiniStat label="Total personal" value={officers.length}/><MiniStat label="În evidență activă" value={officers.filter(o=>o.status!=="Liber").length}/><MiniStat label="Grade distincte" value={new Set(officers.map(o=>o.rank_name)).size}/></div>
    <div className="panel overflow-hidden"><div className="flex flex-wrap items-center justify-between gap-3 p-4"><div className="relative min-w-[220px] flex-1 sm:max-w-sm"><Search size={15} className="absolute left-3 top-3 text-slate-500"/><input className="field pl-9" placeholder="Caută nume, număr, grad..." value={search} onChange={e=>setSearch(e.target.value)}/></div><button className="btn" onClick={onRefresh}>Reîmprospătează</button></div><div className="table-wrap"><table><thead><tr><th>Polițist</th><th>Legitimație</th><th>Grad</th><th>Call sign</th><th>Departament</th><th>Status</th><th>Acțiuni</th></tr></thead><tbody>{officers.map(o=><tr key={o.id}><td className="font-bold">{o.full_name}</td><td>#{o.badge_number}</td><td>{o.rank_name}</td><td>{o.call_sign||"—"}</td><td>{o.department_name}</td><td>{o.status}</td><td><div className="flex flex-wrap gap-2"><button className="btn" onClick={()=>onViewAttendance(o.id)}>Pontaj</button>{canEdit&&<button className="btn btn-primary" onClick={()=>openEdit(o)}>Editează</button>}</div></td></tr>)}{!officers.length&&<tr><td colSpan={7} className="py-10 text-center text-slate-500">Nu există conturi de personal asociate.</td></tr>}</tbody></table></div></div>
    {editing&&<div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4"><form onSubmit={saveEdit} className="panel w-full max-w-2xl space-y-3 p-6"><div className="flex items-center justify-between"><h2 className="text-xl font-black">Editează membru – {editing.full_name}</h2><button type="button" className="btn" onClick={()=>setEditing(null)}>Închide</button></div><div className="grid gap-3 sm:grid-cols-2"><label className="text-sm">Nume complet<input required className="field mt-1" value={draft.full_name} onChange={e=>setDraft({...draft,full_name:e.target.value})}/></label><label className="text-sm">CNP / ID RP<input className="field mt-1" value={draft.cnp} onChange={e=>setDraft({...draft,cnp:e.target.value})}/></label><label className="text-sm">Call sign<input className="field mt-1" value={draft.call_sign} onChange={e=>setDraft({...draft,call_sign:e.target.value})}/></label><label className="text-sm">Număr legitimație<input className="field mt-1" value={draft.badge_number} onChange={e=>setDraft({...draft,badge_number:e.target.value})}/></label><label className="text-sm">Grad<select disabled={!canAssignRank} className="field mt-1" value={draft.rank_id} onChange={e=>setDraft({...draft,rank_id:e.target.value})}><option value="">Grad neatribuit</option>{ranks.map(r=><option key={r.id} value={r.id}>{r.name}</option>)}</select></label><fieldset className="text-sm sm:col-span-2"><legend>Departamente (poate fi încadrat în mai multe)</legend><div className="mt-2 grid gap-2 sm:grid-cols-2">{departments.map(d=><label key={d.id} className="flex items-center gap-2 rounded-lg border border-slate-700 p-2"><input type="checkbox" disabled={!canAssignRank} checked={(draft.department_ids||[]).includes(d.id)} onChange={e=>setDraft({...draft,department_ids:e.target.checked?[...(draft.department_ids||[]),d.id]:(draft.department_ids||[]).filter((x:string)=>x!==d.id)})}/>{d.name}</label>)}</div></fieldset>{canAssignRank&&<fieldset className="text-sm sm:col-span-2"><legend>Certificate acordate</legend><div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-5">{["Radio","MDT","Heli","Moto","HS"].map(cert=><label key={cert} className="flex items-center gap-2 rounded-lg border border-slate-700 p-2"><input type="checkbox" checked={certificates.includes(cert)} onChange={e=>setCertificates(e.target.checked?[...certificates,cert]:certificates.filter(x=>x!==cert))}/>Certificat {cert}</label>)}</div></fieldset>}<label className="text-sm">Data intrării în poliție<input type="date" className="field mt-1" value={draft.joined_at||""} onChange={e=>setDraft({...draft,joined_at:e.target.value})}/></label><label className="text-sm">Status<select className="field mt-1" value={draft.status} onChange={e=>setDraft({...draft,status:e.target.value})}>{["Activ","În serviciu","Liber","Suspendat","Inactiv"].map(x=><option key={x}>{x}</option>)}</select></label></div><p className="muted text-xs">Editarea este disponibilă de la gradul Subcomisar în sus. Politicile RLS din Supabase trebuie să permită aceleași modificări.</p><div className="flex justify-end gap-2"><button type="button" className="btn" onClick={()=>setEditing(null)}>Anulează</button><button className="btn btn-primary">Salvează modificările</button></div>{canAssignRank&&<div className="border-t border-slate-700 pt-3"><div className="flex flex-wrap gap-2"><button type="button" className="btn" onClick={async()=>{const {error}=await supabase!.rpc("manage_officer_career",{p_officer_id:editing.id,p_joined_at:null,p_rank_id:null,p_change:"up"});if(error)alert(error.message);else{alert("UP înregistrat.");setEditing(null);onRefresh();}}}>UP (promovare)</button><button type="button" className="btn" onClick={async()=>{const {error}=await supabase!.rpc("manage_officer_career",{p_officer_id:editing.id,p_joined_at:null,p_rank_id:null,p_change:"down"});if(error)alert(error.message);else{alert("DOWN înregistrat.");setEditing(null);onRefresh();}}}>DOWN (retrogradare)</button></div><p className="muted mt-2 text-xs">Disponibil doar pentru Chestor secundar / Chestor general. Istoric recent: {promotionLog.slice(0,3).map((x:any)=>`${x.change_type} ${x.old_rank_name||"—"} → ${x.new_rank_name||"—"} (${new Date(x.created_at).toLocaleDateString("ro-RO")})`).join(" · ")||"fără modificări"}</p></div>}</form></div>}
  </div>;
}
function InventorySection({section,officers,canManage}:{section:"Echipamente"|"Vehicule";officers:Officer[];canManage:boolean}) {
 const [rows,setRows]=useState<any[]>([]),[name,setName]=useState(""),[code,setCode]=useState(""),[category,setCategory]=useState(section==="Echipamente"?"Stații radio":"Disponibil"),[model,setModel]=useState(""),[plate,setPlate]=useState(""),[assigned,setAssigned]=useState(""),[busy,setBusy]=useState(false),[error,setError]=useState("");
 const table=section==="Echipamente"?"equipment":"vehicles";
 async function load(){if(!supabase)return;const {data,error}=await supabase.from(table).select("*").order("created_at",{ascending:false});if(error)setError(error.message);else{setRows(data||[]);setError("");}}
 useEffect(()=>{load();},[section]);
 async function add(e:React.FormEvent){e.preventDefault();if(!supabase)return;setBusy(true);const payload=section==="Echipamente"?{name,inventory_code:code||null,category,status:"Disponibil",assigned_officer:assigned||null}:{plate_number:plate,model,vehicle_type:category,status:"Disponibil",assigned_officer:assigned||null};const {error}=await supabase.from(table).insert(payload as any);setBusy(false);if(error)setError(error.message);else{setName("");setCode("");setModel("");setPlate("");setAssigned("");load();}}
 async function changeStatus(id:string,status:string){if(!supabase)return;const {error}=await supabase.from(table).update({status}).eq("id",id);if(error)setError(error.message);else load();}
 const title=section==="Echipamente"?"Inventar echipamente":"Flotă auto";
 return <div className="space-y-5"><div><div className="label mb-2">{title.toUpperCase()}</div><h1 className="text-3xl font-black">{section}</h1><p className="muted mt-2 text-sm">Evidență reală și alocare din registrul personalului.</p></div>{error&&<div className="rounded-xl border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-300">{error}</div>}{canManage&&<form onSubmit={add} className="panel grid gap-3 p-5 sm:grid-cols-2"><h2 className="font-bold sm:col-span-2">Adaugă {section==="Echipamente"?"echipament":"vehicul"}</h2>{section==="Echipamente"?<><label className="text-sm">Denumire<input required className="field mt-1" value={name} onChange={e=>setName(e.target.value)}/></label><label className="text-sm">Cod inventar<input className="field mt-1" value={code} onChange={e=>setCode(e.target.value)}/></label><label className="text-sm">Categorie<select className="field mt-1" value={category} onChange={e=>setCategory(e.target.value)}>{["Stații radio","Uniforme","Echipamente protecție","Accesorii","Altele"].map(x=><option key={x}>{x}</option>)}</select></label></>:<><label className="text-sm">Număr înmatriculare<input required className="field mt-1" value={plate} onChange={e=>setPlate(e.target.value)}/></label><label className="text-sm">Model<input required className="field mt-1" value={model} onChange={e=>setModel(e.target.value)}/></label><label className="text-sm">Tip vehicul<input className="field mt-1" value={category} onChange={e=>setCategory(e.target.value)}/></label></>}<label className="text-sm">Alocat membrului<select className="field mt-1" value={assigned} onChange={e=>setAssigned(e.target.value)}><option value="">Nealocat</option>{officers.map(o=><option key={o.id} value={o.id}>{o.full_name} · {o.rank_name}</option>)}</select></label><button disabled={busy} className="btn btn-primary w-fit sm:col-span-2">{busy?"Se salvează…":"Adaugă în registru"}</button></form>}{!canManage&&<p className="panel p-4 text-sm text-slate-400">Inventarul este în mod consultare. Administrarea este disponibilă de la Subcomisar în sus.</p>}<div className="panel divide-y divide-slate-700/50">{rows.map(r=><div key={r.id} className="flex flex-wrap items-center justify-between gap-3 p-4"><div><b>{section==="Echipamente"?r.name:`${r.plate_number} · ${r.model}`}</b><p className="muted mt-1 text-xs">{section==="Echipamente"?`${r.category||"Altele"} · ${r.inventory_code||"Fără cod"}`:r.vehicle_type||"Vehicul"} · {officers.find(o=>o.id===r.assigned_officer)?.full_name||"Nealocat"}</p></div><div className="flex items-center gap-2"><select disabled={!canManage} className="field max-w-44" value={r.status} onChange={e=>changeStatus(r.id,e.target.value)}>{["Disponibil","Alocat","În service","Retras"].map(x=><option key={x}>{x}</option>)}</select>{canManage&&<button type="button" className="btn" onClick={async()=>{if(!confirm("Ștergi definitiv această înregistrare?"))return;const {error}=await supabase!.from(table).delete().eq("id",r.id);if(error)setError("Nu s-a putut șterge: "+error.message);else load();}}>Șterge</button>}</div></div>)}{!rows.length&&<p className="p-5 text-sm text-slate-400">Nu există încă înregistrări. Adaugă primul element.</p>}</div></div>;
}

function OfficerTable({officers,onViewAttendance}:{officers:Officer[];onViewAttendance?:(id:string)=>void}) {
  return <div className="table-wrap"><table><thead><tr><th>Polițist</th><th>Legitimație</th><th>Grad</th><th>Call sign</th><th>Departament</th><th>Status</th>{onViewAttendance&&<th>Pontaj</th>}</tr></thead><tbody>{officers.map(o=><tr key={o.id}><td><div className="flex items-center gap-3"><div className="flex h-9 w-9 items-center justify-center rounded-xl bg-[#273342] text-xs font-black text-blue-300">{o.full_name.split(" ").map(x=>x[0]).slice(0,2).join("")}</div><span className="font-bold">{o.full_name}</span></div></td><td className="font-mono text-slate-300">{o.badge_number?`#${o.badge_number}`:"—"}</td><td>{o.rank_name}</td><td className="font-mono text-blue-300">{o.call_sign||"—"}</td><td className="text-slate-300">{o.department_name}</td><td><span className={`pill ${o.status==="Activ"?"pill-green":o.status==="În serviciu"?"pill-blue":"pill-gray"}`}>{o.status}</span></td>{onViewAttendance&&<td><button className="btn" onClick={()=>onViewAttendance(o.id)}>Vezi pontaj</button></td>}</tr>)}{officers.length===0&&<tr><td colSpan={onViewAttendance?7:6} className="py-10 text-center text-slate-500">Nu există conturi de personal asociate.</td></tr>}</tbody></table></div>;
}
function MiniStat({label,value}:{label:string;value:number}) { return <div className="panel p-4"><div className="label">{label}</div><div className="mt-2 text-2xl font-black">{value}</div></div>; }
function QuickCard({icon:Icon,title,desc,onClick}:{icon:any;title:string;desc:string;onClick:()=>void}) { return <button onClick={onClick} className="panel flex items-center gap-4 p-5 text-left transition hover:border-blue-500/50"><span className="rounded-xl bg-blue-500/10 p-3 text-blue-400"><Icon size={20}/></span><span><span className="block text-sm font-bold">{title}</span><span className="muted mt-1 block text-xs">{desc}</span></span></button>; }

function GenericSection({section, officers, onAdd, role, rankLevel}:{section:Section;officers:Officer[];onAdd:()=>void;role:string;rankLevel:number}) {
  const [departmentRows,setDepartmentRows]=useState<any[]>([]);
  useEffect(()=>{if(section==="Departamente"&&supabase){supabase.from("departments").select("id,name,description").order("name").then(({data,error})=>{if(!error)setDepartmentRows(Array.from(new Map((data||[]).filter((d:any)=>!["intervenții speciale","criminalistică","intervenții criminale","ordine publică","poliția rutieră","poliție rutieră"].includes(String(d.name||"").trim().toLocaleLowerCase("ro-RO"))).map((d:any)=>[String(d.name||"").trim().toLocaleLowerCase("ro-RO"),d])).values()));});}},[section]);
  if(section==="Echipamente"||section==="Vehicule")return <InventorySection section={section} officers={officers} canManage={(rankLevel>=8&&rankLevel<=13)||["super_admin","commander"].includes(role)}/>;
  if(section==="Departamente")return <div className="space-y-6"><div><div className="label mb-2">ORGANIGRAMĂ</div><h1 className="text-3xl font-black">Departamente</h1><p className="muted mt-2 text-sm">Structuri și efective calculate din personalul încadrat.</p></div><div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">{departmentRows.map(d=>{const count=d.name.toLowerCase()==="conducere"?officers.filter(o=>(o.rank_level||0)>=8&&(o.rank_level||0)<=13).length:officers.filter(o=>(o.department_ids||[o.department_id]).includes(d.id)).length;return <div key={d.id} className="panel p-5"><div className="flex items-start justify-between gap-2"><h2 className="font-bold">{d.name}</h2><span className="pill pill-gray">ACTIV</span></div><p className="mt-3 text-3xl font-black">{count}</p><p className="muted mt-1 text-xs">{count===1?"membru încadrat": "membri încadrați"}</p>{d.description&&<p className="muted mt-3 text-sm">{d.description}</p>}</div>})}{!departmentRows.length&&<p className="muted text-sm">Nu există departamente în baza de date.</p>}</div></div>;
  const configs: Record<string,{sub:string;desc:string;icon:any;items:string[]}> = {
    "Grade":{sub:"STRUCTURĂ IERARHICĂ",desc:"Gradele profesionale, gradele distincte de instructor și ordinea de promovare.",icon:Award,items:["Vizitator","Agent","Agent principal","Agent șef adjunct","Agent șef","Subinspector","Inspector","Inspector principal","Subcomisar","Comisar","Comisar-șef","Chestor","Chestor secundar","Chestor general",]},
    "Departamente":{sub:"ORGANIGRAMĂ",desc:"Conducere, DCCO și SAS.",icon:Building2,items:["CONDUCERE","DCCO","Conducere DCCO","SAS","Conducere SAS","INSTRUCTORI","RADIO","MDT","FINAL","HELI","HS"]},
    "Logs":{sub:"JURNAL DE AUDIT",desc:"Evenimente și modificări înregistrate. Acces de la Subcomisar în sus.",icon:Activity,items:["Autentificări","Modificări personal","Acțiuni","Sancțiuni","Decizii"]},
    "Pontaj":{sub:"EVIDENȚA TIMPULUI",desc:"Prezență, ture și ore de serviciu.",icon:Clock3,items:["Ture de zi","Ture de noapte","Ore suplimentare","Concedii","Învoiri"]},
    "Sancțiuni":{sub:"DISCIPLINĂ",desc:"Avertismente și măsuri disciplinare.",icon:Gavel,items:["Avertisment verbal","Avertisment scris","Mustrare","Suspendare","Alte măsuri"]},
    "Dosare":{sub:"EVIDENȚĂ CAUZE",desc:"Dosare și cazuri gestionate de departament.",icon:BriefcaseBusiness,items:["În lucru","În analiză","Soluționat","Arhivat"]},
    "Vehicule":{sub:"FLOTĂ AUTO",desc:"Autovehicule, alocări și stare tehnică.",icon:Car,items:["Disponibil","Alocat","În service","Retras"]},
    "Echipamente":{sub:"INVENTAR",desc:"Echipamente și bunuri alocate personalului.",icon:Package,items:["Stații radio","Uniforme","Echipamente protecție","Accesorii","Altele"]},
    "Recrutări":{sub:"RESURSE UMANE",desc:"Candidați și etapele procesului de recrutare.",icon:UserPlus,items:["Candidat nou","În evaluare","Interviu","Admis","Respins"]},
  };
  const c=configs[section]; const Icon=c?.icon||BookOpen;
  return <div className="space-y-6"><div><div className="label mb-2">{c?.sub||"ADMINISTRARE"}</div><h1 className="text-3xl font-black">{section}</h1><p className="muted mt-2 text-sm">{c?.desc}</p></div>
    <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">{(c?.items||[]).map((item,i)=><div key={item} style={{animationDelay:`${Math.min(i*45,360)}ms`}} className="panel flex items-center gap-4 p-5"><div className="rounded-xl bg-blue-500/10 p-3 text-blue-400"><Icon size={19}/></div><div className="min-w-0 flex-1"><div className="text-sm font-bold">{item}</div><div className="muted mt-1 text-xs">{section==="Grade"?"Nivel "+(i+1):"Categorie configurabilă"}</div></div><span className="pill pill-gray">ACTIV</span></div>)}</div>
    {section==="Logs"&&<div className="panel p-5 text-sm text-slate-400">Jurnalul de audit este disponibil de la Subcomisar în sus.</div>}
  </div>;
}
