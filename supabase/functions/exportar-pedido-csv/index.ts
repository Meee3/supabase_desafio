import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
serve(async (req)=>{
  try {
    const { pedido_id } = await req.json();
    const supabaseClient = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_ANON_KEY') ?? '', {
      global: {
        headers: {
          Authorization: req.headers.get('Authorization')
        }
      }
    });
    const { data: detalhesPedido, error } = await supabaseClient.from('detalhes_pedido').select('*').eq('pedido_id', pedido_id);
    if (error) throw error;
    if (!detalhesPedido || detalhesPedido.length === 0) {
      return new Response(JSON.stringify({
        erro: 'Pedido não encontrado'
      }), {
        status: 404,
        headers: {
          'Content-Type': 'application/json'
        }
      });
    }
    const cabecalhos = [
      'ID do Pedido',
      'Data',
      'Status',
      'Cliente',
      'Email',
      'Telefone',
      'Produto',
      'Quantidade',
      'Preco Unitario',
      'Subtotal',
      'Total do Pedido'
    ];
    const linhasCSV = [
      cabecalhos.join(',')
    ];
    detalhesPedido.forEach((item, indice)=>{
      const linha = [
        item.pedido_id.substring(0, 8).toUpperCase(),
        new Date(item.data_pedido).toLocaleDateString('pt-BR'),
        item.status,
        `"${item.nome_cliente}"`,
        item.email_cliente,
        item.telefone_cliente || 'N/A',
        `"${item.nome_produto}"`,
        item.quantidade,
        item.preco_unitario.toFixed(2),
        item.subtotal.toFixed(2),
        indice === 0 ? item.valor_total.toFixed(2) : ''
      ];
      linhasCSV.push(linha.join(','));
    });
    const csv = linhasCSV.join('\n');
    return new Response(csv, {
      headers: {
        'Content-Type': 'text/csv; charset=utf-8',
        'Content-Disposition': `attachment; filename="pedido_${pedido_id.substring(0, 8)}.csv"`
      },
      status: 200
    });
  } catch (erro) {
    return new Response(JSON.stringify({
      erro: erro.message
    }), {
      headers: {
        'Content-Type': 'application/json'
      },
      status: 400
    });
  }
});
