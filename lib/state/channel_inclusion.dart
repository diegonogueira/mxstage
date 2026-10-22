/// O canal está no **meu fone**? Por mesa+bus (cada bus é o retorno de uma
/// pessoa). Nasceu do culto de 21/10: o DM (talkback do operador) chiava no
/// fone e o violão, desligado na mesa pro bus, nunca aparecia.
enum ChannelInclusion {
  /// Segue a mesa: o envio que o operador deixou (desligado continua desligado).
  auto,

  /// "No meu fone": incluir e equalizar mesmo se estiver desligado na mesa.
  include,

  /// "Fora do meu fone": zerado no meu retorno e ignorado pelo Equalizar.
  exclude,
}
